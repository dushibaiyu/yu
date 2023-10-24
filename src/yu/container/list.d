module yu.container.list;

public import containers.slist;
import containers.internal.node : shouldAddGCRange;

alias List = SList;


void clear(T,ALLOC,bool supportGC = shouldAddGCRange!T)(ref DynamicArray!(T,ALLOC,supportGC) array)
{
    array.resize(0);
}
