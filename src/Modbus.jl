"""
Modbus.jl is an interface to the [libmodbus](http://www.libmodbus.org) C library.
"""
module Modbus

export MODBUS_TCP_DEFAULT_PORT,
       modbus_new_tcp, modbus_connect, modbus_read_registers,
       modbus_close, modbus_free, modbus_set_slave, modbus_convert_regs

"""
Mirror of `struct timeval` found in sys/time.h.
"""
type Ctimeval
    tv_sec::Clong    
    tv_usec::Clong
end

"""
Mirror of `modbus_t` found in modbus-private.h.
"""
type CModbusCtx
    slave::Cint
    s::Cint
    debug::Cint
    error_recovery::Cint
    response_timeout::Ctimeval
    byte_timeout::Ctimeval
    backend::Ptr{Void}
    backend_data::Ptr{Void}
end

# CModbusCtx  may not  be the  right  mirror for  the corresponding  C
# struct on certain  systems. The below raw pointer  typealias is used
# by  default for  passing to  the  C calls  and can  be converted  to
# CModbusCtx if required.

"""
The Modbus context type.
"""
typealias ModbusCtx Ptr{Void}

"""
The register type: 16-bit
"""
typealias Register Cushort

"""
Default port number for Modbus TCP.
"""
const MODBUS_TCP_DEFAULT_PORT = 502

"""
Returns a `ModbusCtx` object given the `ip` address and the `port`. Default 
`port` is `MODBUS_TCP_DEFAULT_PORT` (502).
"""
function modbus_new_tcp(ip::String, port=MODBUS_TCP_DEFAULT_PORT)
    c_ip = convert(Ptr{Cchar}, ip)
    c_port = convert(Cint, port)
    modbus_ctx = ccall((:modbus_new_tcp, "libmodbus"), ModbusCtx,
                       (Ptr{Cchar}, Cint, ), c_ip, c_port)

    if (modbus_ctx == C_NULL)
        error("`modbus_new_tcp` returned a null pointer.")
    end

    return modbus_ctx
end

"""
Set the slave unit id `slave`.
"""
function modbus_set_slave(ctx::ModbusCtx, slave)
    c_slave = convert(Cint, slave)
    status = ccall((:modbus_set_slave, "libmodbus"), Cint, (ModbusCtx, Cint, ),
                   ctx, c_slave)
    if (status == -1)
        error("`modbus_set_slave` failed. Returned -1.")
    end
end

"""
Connects the backend of the modbus context `ctx`.
"""
function modbus_connect(ctx::ModbusCtx)
    status = ccall((:modbus_connect, "libmodbus"), Cint, (ModbusCtx, ), ctx)

    if (status == -1)
        error("`modbus_connect` failed. Returned -1.")
    end
end

"""
Reads the holding registers of remote device and puts the data into an array.
 `addr` is the address of the starting register. `nb` is the number of registers
 to read. Returns a julia array containing the read data.
"""
function modbus_read_registers(ctx::ModbusCtx, addr, nb)
    c_addr = convert(Cint, addr)
    c_nb = convert(Cint, nb)
    dest = zeros(Register, nb)
    status = ccall((:modbus_read_registers, "libmodbus"), Cint,
                   (ModbusCtx, Cint, Cint, Ptr{Register}, ),
                   ctx, c_addr, c_nb, pointer(dest))

    if (status == -1)
        error("`modbus_read_registers` failed. Returned -1.")
    end

    return dest
end

"""
Close the modbus connection opened with modbus connect.
"""
function modbus_close(ctx::ModbusCtx)
    ccall((:modbus_close, "libmodbus"), Void, (ModbusCtx, ), ctx)
end

"""
Free the memory allocated to `ctx` by `modbus_new_tcp`.
"""
function modbus_free(ctx::ModbusCtx)
    ccall((:modbus_free, "libmodbus"), Void, (ModbusCtx, ), ctx)
end

"""
Return an array whose elements are of type `typ` given the 16-bit
 register array `regs`.
"""
function modbus_convert_regs(regs::Array{Register}, typ::DataType)
    nbytes = sizeof(typ)
    ret_arr = None

    if nbytes == 1 # Cchar or Cuchar
        ret_arr = Array(typ, length(regs) * 2)

        for i = 1:length(regs)
            ret_arr[2*i - 1] = convert(typ, regs[i] >> 8) # MSB
            ret_arr[2*i] = convert(typ, regs[i]) # LSB
        end

    elseif nbytes == 2 # Cshort, Cushort or Float16
        return map(x -> reinterpret(typ, x), regs)

    elseif nbytes == 4 # Cint, Cuint or Cfloat
        if (length(regs) % 2) != 0
            error("Size of array not a multiple of 4,2 cannot convert to $typ")
        end

        ret_arr = Array(typ, convert(Int, trunc(length(regs) / 2)))

        for i = 1:2:length(regs)
             val = reinterpret(typ, (convert(Cuint, regs[i]) << 16)
                                     | convert(Cuint, regs[i+1]))
             ret_arr[convert(Int, trunc(i/2)) + 1] = val
        end

    elseif nbytes == 8 # Clong, Culong or Cdouble
        if (length(regs) % 4) != 0
            error("Size of array not a multiple of 4, cannot convert to $typ")
        end
        ret_arr = Array(typ, convert(Int, trunc(length(regs) / 4)))

        for i = 1:4:length(regs)
            ret_arr[convert(Int, trunc(i/4)) + 1] = reinterpret(typ, 
                                           (convert(Culong, regs[i]) << 48) | 
                                           (convert(Culong, regs[i+1]) << 32) |
                                           (convert(Culong, regs[i]) << 16) |
                                           convert(Culong, regs[i+3]))
        end

    else
        error("`get_regs_as` type $typ not supported!")
    end

    return ret_arr
end

end # end module
