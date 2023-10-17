import std.stdio;
import yu.utils.sharedlib;
import std.string;
import yu.utils.buffer.mmapbuffer;


alias getVersion = char * function() @nogc nothrow;

void main()
{
	writeln("Edit source/app.d to start your project.");

	auto lib = SharedLib("libcurl.so");
	writeln("is load : ", lib.isValid);
	if(lib.isValid){
		auto ver = lib.getFunction!getVersion("curl_version");
		writeln(fromStringz(ver()));
	}



    import std.file;
    auto name = "./addd.tp";
    scope(exit) std.file.remove(name);
	std.file.write(name, "abcd");
	MmapBuffer mmf = MmapBuffer(name);
	auto dt = mmf.dataPtr;
	string  testData = "77889910232384638748234";
	mmf.write(cast(const ubyte[])(testData));
	auto p = cast(string) dt[0 .. testData.length];
	assert(p == testData);
	ubyte[] t = new ubyte[testData.length];
	mmf.write(cast(const ubyte[])(testData));
	auto tlen = cast(ulong)mmf.read(t);
	assert(tlen == t.length);
	assert(cast(string)(t) == testData);
	tlen = cast(ulong)mmf.read(t);
	assert(tlen == t.length);
	assert(cast(string)(t) == testData);
	mmf.restRead(0);
	tlen = cast(ulong)mmf.read(t);
	assert(tlen == t.length);
	assert(cast(string)(t) == testData);
	tlen = cast(ulong)mmf.read(t);
	assert(tlen == t.length);
	assert(cast(string)(t) == testData);
}
