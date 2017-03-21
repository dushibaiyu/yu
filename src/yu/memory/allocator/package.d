module yu.memory.allocator;

public import std.experimental.allocator;

shared static this()
{
	_yuAlloctor = processAllocator;
}


@property IAllocator yuAlloctor(){
	return _yuAlloctor;
}


@property void yuAlloctor(IAllocator alloctor){
	_yuAlloctor = alloctor; 
}

private:
__gshared IAllocator _yuAlloctor; 