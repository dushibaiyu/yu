module smartref.util;

import std.traits;
import std.typecons;
import std.meta;

template Pointer(T) {
	static if(is(T == class) || is(T == interface)){
		alias Pointer = T;
	} else {
		alias Pointer = T *;
	}
}

template isInheritClass(T, Base)
{
	enum FFilter(U) = is(U == Base);
	enum isInheritClass = (Filter!(FFilter, BaseTypeTuple!T).length > 0);
} 
