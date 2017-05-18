import std.stdio;
import yu.tools.sharedlib;
import std.string;

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
}
