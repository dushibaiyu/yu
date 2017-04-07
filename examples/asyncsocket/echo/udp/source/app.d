import std.stdio;

import std.socket;
import std.conv;

import yu.asyncsocket.udpsocket;
import yu.eventloop;
import yu.memory.allocator;
import std.experimental.allocator.mallocator;

void main()
{
	yuAlloctor = allocatorObject(Mallocator.instance);
   	EventLoop loop = yNew!EventLoop();
	scope(exit) yDel(loop);
	UDPSocket server = yNew!UDPSocket(loop);
	scope(exit) yDel(server);
	UDPSocket client = yNew!UDPSocket(loop);
	scope(exit) yDel(client);

	Address adr = yNew!InternetAddress("127.0.0.1", cast(ushort)9008);
	scope(exit) yDel(adr);

    server.bind(adr);
    
    int i = 0;
    
    void serverHandle(ubyte[] data, Address adr2)
    {
		scope(exit) yDel(adr2);
		writeln("from clinet: addr ", cast(void *)adr2);
		writeln("from clinet: ", adr2.toString);
        string tstr = cast(string)data;
        writeln("Server revec data : ", tstr);
        string str = "hello " ~ i.to!string();
        server.sendTo(data,adr2);
        assert(str == tstr);
        if(i > 10)
            loop.stop();
    }
    
    void clientHandle(ubyte[] data, Address adr23)
    {
		scope(exit) yDel(adr23);
        writeln("Client revec data : ", cast(string)data);
        ++i;
        string str = "hello " ~ i.to!string();
        client.sendTo(str);
    }

    client.setReadCallBack(&clientHandle);
    server.setReadCallBack(&serverHandle);
    
    client.start();
    server.start();
    
    client.connect(adr);
    string str = "hello " ~ i.to!string();
    client.sendTo(cast(ubyte[])str);
    writeln("Edit source/app.d to start your project.");
    loop.run();
    server.close();
    client.close();
}
