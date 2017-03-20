﻿module smartref;

import std.experimental.allocator;

public import smartref.scopedref;
public import smartref.sharedref;
public import smartref.common;
import smartref.util;

alias SharedRef(T) = ISharedRef!(typeof(SmartGCAllocator.instance),T);
alias WeakRef(T) = IWeakRef!(typeof(SmartGCAllocator.instance),T);
alias EnableSharedFromThis(T) = IEnableSharedFromThis!(typeof(SmartGCAllocator.instance),T);
alias ScopedRef(T) = IScopedRef!(typeof(SmartGCAllocator.instance),T);

// alias
auto makeSharedRef(T,Args...)(auto ref Args args){
	return SharedRef!(T)(SmartGCAllocator.instance.make!T(args));
}

auto makeScopedRef(T,Args...)(auto ref Args args){
	return ScopedRef!(T)(SmartGCAllocator.instance.make!T(args));
}

auto makeSharedRefWithDeleter(T,Args...)(auto ref Args args){
	static assert(args.length > 0);
	static assert(is(typeof(args[0]) == void function(ref typeof(SmartGCAllocator.instance),Pointer!T) nothrow));
	return SharedRef!(T)(SmartGCAllocator.instance.make!T(args[1..$]),args[0]);
}

auto makeScopedRefWithDeleter(T,Args...)(auto ref Args args){
	static assert(args.length > 0);
	static assert(is(typeof(args[0]) == void function(ref typeof(SmartGCAllocator.instance),Pointer!T) nothrow));
	return ScopedRef!(T)(SmartGCAllocator.instance.make!T(args[1..$]),args[0]);
}

// I
auto makeISharedRef(T,Alloc,Args...)(auto ref Alloc alloc,auto ref Args args){
	Pointer!T value = alloc.make!T(args);
	static if(stateSize!Alloc == 0){
		return ISharedRef!(Alloc,T)(value);
	} else {
		return ISharedRef!(Alloc,T)(alloc,value);
	}
}

auto makeIScopedRef(T,Alloc,Args...)(auto ref Alloc alloc,auto ref Args args){
	Pointer!T value = alloc.make!T(args);
	static if(stateSize!Alloc == 0){
		return IScopedRef!(Alloc,T)(value);
	} else {
		return IScopedRef!(Alloc,T)(alloc,value);
	}
}

auto makeISharedRefWithDeleter(T,Alloc,Args...)(auto ref Alloc alloc,auto ref Args args){
	static assert(args.length > 0);
	static assert(is(typeof(args[0]) == void function(ref Alloc,Pointer!T) nothrow));
	Pointer!T value = alloc.make!T(args[1..$]);
	static if(stateSize!Alloc == 0){
		return ISharedRef!(Alloc,T)(value,args[0]);
	} else {
		return ISharedRef!(Alloc,T)(alloc,value,args[0]);
	}
}

auto makeIScopedRefWithDeleter(T,Alloc,Args...)(auto ref  Alloc alloc,auto ref Args args){
	static assert(args.length > 0);
	static assert(is(typeof(args[0]) == void function(ref Alloc,Pointer!T) nothrow));
	Pointer!T value = alloc.make!T(args[1..$]);
	static if(stateSize!Alloc == 0){
		return IScopedRef!(Alloc,T)(value,args[0]);
	} else {
		return IScopedRef!(Alloc,T)(alloc,value,args[0]);
	}
}

version(unittest){
	import std.stdio;
	import std.experimental.allocator;
	import std.experimental.allocator.gc_allocator;
	import std.exception;

	void smartfreeSharedInt(ref typeof(SmartGCAllocator.instance) alloc, int * d)nothrow {
		collectException({
				writeln("free the int");
				alloc.dispose(d);
			}());
	}
	
	void freeSharedInt(ref typeof(GCAllocator.instance) alloc, int * d)nothrow {
		collectException({
				writeln("free the int");
				alloc.dispose(d);
			}());
	}

	class TestMyClass : IEnableSharedFromThis!(typeof(SmartGCAllocator.instance),TestMyClass)
	{
		mixin EnableSharedFromThisImpl;
		shared this(int t){
			i = t;
			writeln("create TestMyClass i = ", i);
		}

		this(int t){
			i = t;
			writeln("create TestMyClass i = ", i);
		}

		~this(){
			writeln("free TestMyClass i = ", i);
		}

		int i = 0;
	}
}

unittest{
	import std.stdio;
	import std.experimental.allocator;
	import std.experimental.allocator.gc_allocator;
	import std.exception;
	

	{
		//auto malloc = 
		auto a = GCAllocator.instance.makeISharedRefWithDeleter!(int)(&freeSharedInt,10);
		assert(*a == 10);
		auto c = a.castTo!(uint)();
		*c = uint.max;
		uint t = cast(uint)(*a);
		assert(t == uint.max);
		auto b = GCAllocator.instance.makeISharedRef!int(100);
		assert(*b == 100);
		auto a1 = makeSharedRefWithDeleter!(int)(&smartfreeSharedInt,10);
		assert(*a1 == 10);
		auto b1 = makeSharedRef!int(100);
		assert(*b1 == 100);
		
	}
	writeln("Edit source/app.d to start your project.");
	
	
	auto a = makeIScopedRefWithDeleter!(int)(GCAllocator.instance,&freeSharedInt);
	auto a1 = makeScopedRefWithDeleter!(int)(&smartfreeSharedInt);
	{
		auto aclass = makeScopedRef!TestMyClass(10);
		aclass.i = 500;
	}

	{
		auto sclass = makeSharedRef!(shared TestMyClass)(100);
		sclass.i = 1000;

		auto sobj = sclass.castTo!(shared Object)();
		//auto nsared = sclass.castTo!(TestMyClass)(); , erro mast all sheref or not

		SharedRef!TestMyClass t  = makeSharedRef!TestMyClass(400);
		t.i = 50;
		auto th = t.sharedFromThis();
		auto tobj = th.castTo!(Object)();
		th.i = 30;
	}
}