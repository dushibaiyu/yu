module yu.asyncsocket.transport;

import yu.eventloop;
public import yu.memory.allocator;

enum TransportType : short
{
    ACCEPT,
    TCP,
    UDP
}

__gshared size_t TCP_READ_BUFFER_SIZE = 16 * 1024;
__gshared size_t  UDP_READ_BUFFER_SIZE = 16 * 1024;



abstract class AsyncTransport
{
    this(EventLoop loop, TransportType type)
    {
        _loop = loop;
    }

    void close();
    bool start();
    @property bool isAlive() @trusted;
    @property int fd();

    final @property transportType()
    {
        return _type;
    }

    final @property eventLoop()
    {
        return _loop;
    }
protected:
    EventLoop _loop;
    TransportType _type;
}

static if (IOMode == IO_MODE.epoll)
{
    version (X86)
    {

        enum SO_REUSEPORT = 15;
    }
    else version (X86_64)
    {
        enum SO_REUSEPORT = 15;
    }
    else version (MIPS32)
    {
        enum SO_REUSEPORT = 0x0200;

    }
    else version (MIPS64)
    {
        enum SO_REUSEPORT = 0x0200;
    }
    else version (PPC)
    {
        enum SO_REUSEPORT = 15;
    }
    else version (PPC64)
    {
        enum SO_REUSEPORT = 15;
    }
    else version (ARM)
    {
        enum SO_REUSEPORT = 15;
    }
}
else static if (IOMode == IO_MODE.kqueue)
{
    enum SO_REUSEPORT = 0x0200;
}

mixin template TransportSocketOption()
{
    import std.functional;
    import std.datetime;
    import core.stdc.stdint;
	import std.socket;
	version(Windows)
		import SOCKETOPTIONS = core.sys.windows.winsock2;
	version(Posix) 
		import SOCKETOPTIONS = core.sys.posix.sys.socket;


    /// Get a socket option.
    /// Returns: The number of bytes written to $(D result).
    //returns the length, in bytes, of the actual result - very different from getsockopt()
    pragma(inline) final int getOption(SocketOptionLevel level,
        SocketOption option, void[] result) @trusted
    {

        return _socket.getOption(level, option, result);
    }

    /// Common case of getting integer and boolean options.
    pragma(inline) final int getOption(SocketOptionLevel level,
        SocketOption option, ref int32_t result) @trusted
    {
        return _socket.getOption(level, option, result);
    }

    /// Get the linger option.
    pragma(inline) final int getOption(SocketOptionLevel level,
        SocketOption option, ref Linger result) @trusted
    {
        return _socket.getOption(level, option, result);
    }

    /// Get a timeout (duration) option.
    pragma(inline) final void getOption(SocketOptionLevel level,
        SocketOption option, ref Duration result) @trusted
    {
        _socket.getOption(level, option, result);
    }

    /// Set a socket option.
    pragma(inline) final void setOption(SocketOptionLevel level,
        SocketOption option, void[] value) @trusted
    {
        return _socket.setOption(forward!(level, option, value));
    }

    /// Common case for setting integer and boolean options.
    pragma(inline) final void setOption(SocketOptionLevel level,
        SocketOption option, int32_t value) @trusted
    {
        return _socket.setOption(forward!(level, option, value));
    }

    /// Set the linger option.
    pragma(inline) final void setOption(SocketOptionLevel level,
        SocketOption option, Linger value) @trusted
    {
        return _socket.setOption(forward!(level, option, value));
    }

    pragma(inline) final void setOption(SocketOptionLevel level,
        SocketOption option, Duration value) @trusted
    {
        return _socket.setOption(forward!(level, option, value));
    }

	// you should be yDel the Address
	final @property @trusted Address remoteAddress()
	{
		Address addr = createAddress();
		SOCKETOPTIONS.socklen_t nameLen = addr.nameLen;
		if (Socket.ERROR == SOCKETOPTIONS.getpeername(_socket.handle, addr.name, &nameLen))
			throw new SocketOSException("Unable to obtain remote socket address");
		if (nameLen > addr.nameLen)
			throw new SocketParameterException("Not enough socket address storage");
		assert(addr.addressFamily == _socket.addressFamily);
		return addr;
	}
	
	// you should be yDel the Address
	final @property @trusted Address localAddress()
	{
		Address addr = createAddress();
		SOCKETOPTIONS.socklen_t nameLen = addr.nameLen;
		if (Socket.ERROR == SOCKETOPTIONS.getsockname(_socket.handle, addr.name, &nameLen))
			throw new SocketOSException("Unable to obtain local socket address");
		if (nameLen > addr.nameLen)
			throw new SocketParameterException("Not enough socket address storage");
		assert(addr.addressFamily == _socket.addressFamily);
		return addr;
	}

	protected final Address createAddress()
	{
		enum ushort DPORT = 0;
		if(AddressFamily.INET == _socket.addressFamily)
			return yNew!InternetAddress(DPORT);
		else if (AddressFamily.INET6 == _socket.addressFamily)
			return yNew!Internet6Address(DPORT);
		else
			throw new AddressException("NOT SUPPORT addressFamily. It only can be AddressFamily.INET or AddressFamily.INET6");
	}
}
