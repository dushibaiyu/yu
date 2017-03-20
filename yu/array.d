module yu.array;

/**
 * 移除数组中元素，并且数组下标前移。
 * return： 移除的个数
 * 注： 对数组的长度不做处理
*/
size_t arrayRemove(E)(ref E[] ary, E e)
{
    size_t len = ary.length;
    size_t site = 0;
    size_t rm = 0;
    for (size_t j = site; j < len; ++j)
    {
        if(ary[j] != e) {
            ary[site] = ary[j];
            site ++;
        } else {
            rm ++;
        }
    }
	return rm;
}

ptrdiff_t findIndex(E)(in E[] ary, in E e)
{
	ptrdiff_t index = -1;
	for(size_t id = 0; id < ary.length; ++id)
	{
		if(e == data[id]){
			index = cast(ptrdiff_t)id;
			break;
		}
	}
	return index;
}

unittest
{
    import std.stdio;
    
    int[] a = [0,0,0,4,5,4,0,8,0,2,0,0,0,1,2,5,8,0];
    writeln("length a  = ", a.length, "   a is : ", a);
    int[] b = a.dup;
    auto rm = arrayRemove(b,0);
	b = b[0..($-rm)];
    writeln("length b  = ", b.length, "   b is : ", b);
    assert(b == [4, 5, 4, 8, 2, 1, 2, 5, 8]);
    
    int[] c = a.dup;
    rm = arrayRemove(c,8);
	c = c[0..($-rm)];
    writeln("length c  = ", c.length, "   c is : ", c);
    
    assert(c == [0, 0, 0, 4, 5, 4, 0, 0, 2, 0, 0, 0, 1, 2, 5, 0]);
    
     int[] d = a.dup;
     rm = arrayRemove(d,9);
	 d = d[0..($-rm)];
     writeln("length d = ", d.length, "   d is : ", d);
     assert(d == a);
}
