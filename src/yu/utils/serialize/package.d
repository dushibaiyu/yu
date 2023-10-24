module yu.utils.serialize;

public import yu.utils.serialize.write;
public import yu.utils.serialize.read;
public import yu.utils.serialize.types;

/**
 *  按照顺序写入和读出，不关心原来的变量名的，不记录写的顺序。
 *  存储基本大端字节序存储。
 *  二进制格式：
 * 对于基本和内置组合类型： 数据的长度是固定的。
 *             类型头  数据部分
 * 				00    __data__
 * 				类型头的定义见type.d 文件
 *  Struct 组合类型：
 * 			   类型头  数据部分	结束标志（Types.End）
 * 				0x0F    __data__  0x00
 * 			结构提在写入的时候是每个成员都按照顺序写入，元素是结构提也是嵌套写入，数组一样。
 *  Array 数组类型：
 * 				类型头 元素的类型标志 元素的个数（4Byte）  数据部分  结束标志（Types.End）
 * 				0x10 	 00        	00 00 00 00       __data__     0x00
 * 			如果数组成员是结构体或者数组，记录的也只是Type.Struct和Types.Array, 其__data__部分也是和单独写一样的遵照标志写的是全部的和单独一样，
 * 				对于结构体不关系结构体的结构信息，根据类型头和结束标志区分。数组一样，不关系数组的类型长度，只根据开始和结束标志区分。
 * 			对于基本类型和内置组合类型，数据部分和单独写不一样的，省略其类型信息，类型信息根据数组的“元素的类型标志”获取的，即认为每个元素类型是一致的，元素自己的长度是固定的。
 *
 *  例子：
 *  对于TAT 结构的二进制后的数据：
 * 	15, // TAT 开始的标志， 0x0F
 *
 *  	15 // TAT.ta第一个元素ta的开始标志 TA 类型： 0x0F
 * 			13,   0, 1, 1, 1,  // TAT.TA.de ,Date类型：0x0D（13）， 数据4位
 * 			16 // TAT.TA.data 数组类型，尅是标志0X10（16）
 * 				2 // TAT.TA.data 的元素类型： ubyte （0x02）
 * 				0, 0, 0, 5, //AT.TA.data 的元素个数： 5 个
 * 				0, 1, 3, 4, 5, //AT.TA.data  data 数据不部分
 * 			00	// TAT.TA.data  的结束标志位
 * 			16 //TAT.TA.str 数组开始类型头  Note： string 不可变的 char数组
 * 				1 // TAT.TA.str 元素类型： char
 * 				0, 0, 0, 11, // TAT.TA.str 元素个数
 * 				104, 101, 108, 108, 111, 32, 119, 111, 114, 108, 100 // TAT.TA.str 数据部分
 * 			0 // TAT.TA.str 结束标志
 * 			11,   64, 41, 40, 245, 194, 143, 92, 41, //TAT.TA.db  double数据类型 0x0B（11），后面8位为数据部分
 * 			8,   0, 0, 0, 0, 0, 0, 3, 129, //TAT.TA.lo  long类型 0x08（8），后面8位为数据部分
 * 			3, 0, // TAT.TA.bl bool类型 0x03（3） ， 0 是 flase
 * 			7, 0, 0, 0, 90,// TAT.TA.ui  uint类型 0x07（7） ， 剩下的是数据部分
 * 			15, // TAT.TA.ta 结构体开始标志位
 * 				10,  62, 131, 18, 111, // TAT.TA.TT.ft  float类型0x0A(10)，4个字节长度
 * 				14,  7, 223, 2, 15, 10, 25, 30, // TAT.TA.TT.dt  DateTime类型0x0E(14)，7个字节长度
 * 			0, // TAT.TA.ta 结构体结束标志位
 * 			16 // TAT.TA.iarry 数组开始标志位
 * 				6 // TAT.TA.iarry 数组的元素类型 int ： 0x06(6)
 * 				0, 0, 0, 10,  // TAT.TA.iarry 数据长度
 * 				0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 2, 0, 0, 0, 3, 0, 0, 0, 4, 0, 0, 0, 5, 0, 0, 0, 6, 0, 0, 0, 7, 0, 0, 0, 8, 0, 0, 0, 9,// TAT.TA.iarry 数据部分
 * 			0 //TAT.TA.iarry 结束标志
 * 		0// TAT.ta 结构体结束标志
 *
 * 		16// TAT.tt 数组的开始标志
 * 			15 // TAT.tt 数组元素类型
 * 			0, 0, 0, 3, TAT.tt 数组元素长度
 * 			15 // TAT.tt[0] 开始标志
 * 				10， 62, 131, 18, 111, // TAT.tt[0].ft
 * 				14,  7, 223, 2, 15, 10, 25, 30, // TAT.tt[0].dt
 * 			00 // TAT.tt[0] 开结束标志
 * 			15,  10, 63, 160, 196, 156, 14, 7, 224, 2, 15, 10, 25, 30,   0, // TAT.tt[1]
 * 			15, 10, 64, 16, 98, 78, 14, 7, 225, 2, 15, 10, 25, 30, 0, // TAT.tt[2]
 * 		0 // TAT.tt 数组的结束标志
 *
 * 		16, // TAT.ttt 数组的开始标志
 * 			16 // TAT.ttt 数组的元素类型， 还是数组，数组嵌套
 * 			0, 0, 0, 2, //TAT.ttt 数组长度
 * 			16	//TAT.ttt[0] 开始标志
 * 				15 // TAT.ttt[0] 的元素类型， 结构体
 * 				0, 0, 0, 3 // TAT.ttt[0] 的元素个数
 * 				15,   10, 62, 131, 18, 111, 14, 7, 223, 2, 15, 10, 25, 30,   0, //TAT.ttt[0][0] 结构提类型
 * 				15, 10, 62, 182, 69, 162, 14, 7, 224, 2, 15, 10, 25, 30, 0, //TAT.ttt[0][1]
 * 				15, 10, 62, 233, 120, 213, 14, 7, 225, 2, 15, 10, 25, 30, 0, //TAT.ttt[0][2]
 * 			0  //TAT.ttt[0] 结束标志
 * 			16 //TAT.ttt[1] 开始标志
 * 				15 TAT.ttt[1] 的元素类型， 结构体
 * 				0, 0, 0, 3 // TAT.ttt[1] 的元素个数
 * 				15, 10, 63, 160, 196, 156, 14, 7, 226, 2, 15, 10, 25, 30, 0, //TAT.ttt[1][0]
 * 				15, 10, 63, 173, 145, 104, 14, 7, 227, 2, 15, 10, 25, 30, 0, //TAT.ttt[1][1]
 * 				15, 10, 64, 22, 200, 180, 14, 7, 228, 10, 2, 10, 25, 30, 0, //TAT.ttt[1][2]
 * 			0 //TAT.ttt[1] 结束标志
 * 		0// TAT.ttt 数组的结束标志
 *
 *  0 // TAT 结束标志
 *
*/


version(unittest)
{
	import yu.utils.serialize.build;
	import std.experimental.allocator.mallocator;
	import std.stdio;
	struct TT
	{
		float ft;
		DateTime dt;
		mixin Serialize!TT;
	}

    struct TT2
    {
        float ft;
        DateTime dt;
        int tt2;
        mixin Serialize!TT2;
    }

	struct TA
	{
		Date de;
		ubyte[] data;
		string str;
		double db;
		long lo;
		bool bl;
		uint ui;


		TT ta;

		int[] iarry;

		mixin Serialize!TA;
	}


	struct TAT
	{
		enum AA = 10;
		TA ta;
		TT[] tt;
		TT[][] ttt;
		mixin Serialize!TAT;

		void intd()
		{}

		int getD()
		{
                    return 0;
		}
	}



	void testTAT()
	{
		TA ta;
		ta.data = [0x00,0x01,0x03,0x04,0x05];
		ta.str = "hello world";
		ta.db = 12.58;
		ta.lo = 897;
		ta.bl = false;
		ta.ui = 90;
		ta.ta = TT(0.256f,DateTime(2015,2,15,10,25,30));
		ta.iarry = [0,1,2,3,4,5,6,7,8,9];

		TAT tat;
		tat.ta = ta;
		tat.tt = [TT(0.256f,DateTime(2015,2,15,10,25,30)),TT(1.256f,DateTime(2016,2,15,10,25,30)),TT(2.256f,DateTime(2017,2,15,10,25,30))];
		tat.ttt = new TT[][2];
		tat.ttt[0] = [TT(0.256f,DateTime(2015,2,15,10,25,30)),TT(0.356f,DateTime(2016,2,15,10,25,30)),TT(0.456f,DateTime(2017,2,15,10,25,30))];
		tat.ttt[1] = [TT(1.256f,DateTime(2018,2,15,10,25,30)),TT(1.356f,DateTime(2019,2,15,10,25,30)),TT(2.356f,DateTime(2020,10,2,10,25,30))];
		auto buffer = new Buffer!Mallocator();
		WriteStream strem = WriteStream(buffer);
		TAT.serialize(tat,&strem);
        ubyte[] data = cast(ubyte[])(buffer.allData);
		writeln("---------TAT.unSerialize----------");
		writeln("sridata is : \n", data);
		TAT ttat;
		ReadStream steam = ReadStream(data);

		TAT.unSerialize(&ttat,&steam);
		writeln("AA ", TAT.AA);
		writeln("ttat.ta.data = ", ttat.ta.data);
		writeln("ttat.ta.iarry = ", ttat.ta.iarry);
		writeln("ttat.ta.str = ", ttat.ta.str);
		writeln("ttat.ta.ta.ft = ", ttat.ta.ta.ft);
		writeln("ttat.ta.ta.dt = ", ttat.ta.ta.dt.toISOExtString());
		writeln("ttat.ta.db = ", ttat.ta.db);
		writeln("ttat.ta.ui = ", ttat.ta.ui);
		writeln("ttat.tt.length = ",ttat.tt.length );
		writeln("ttat.tt[0].date = ",ttat.tt[0].dt );
		writeln("ttat.ttt[0][0].date = ",ttat.ttt[0][0].dt );
    }

	void seriTT(ref TT t, WriteStream * strem)
	{
		strem.startStruct();
		scope(exit)strem.endStruct();
		strem.write!float(t.ft);
		strem.write!DateTime(t.dt);
	}

	TA readTA(ReadStream * strem)
	{
		TA t;
		strem.startReadStruct();
		t.de = strem.read!(Date)();
		t.data = strem.read!(ubyte[])();
		t.str = strem.read!(string)();
		t.db = strem.read!(double)();
		t.lo = strem.read!(long)();
		t.bl = strem.read!(bool)();
		t.ui = strem.read!(uint)();
		//	strem.append(seriTT(t.ta,&strem));
		t.ta = readTT(strem);
		uint len = strem.startReadArray();
		t.iarry = new int[len];
		foreach(i;0..len)
		{
			t.iarry[i] = strem.read!(int)();
		}
		return t;
	}

	TT readTT(ReadStream * strem)
	{
		TT t;
		strem.startReadStruct();
		t.ft = strem.read!float();
		t.dt = strem.read!DateTime();
		strem.endReadStruct();
		return t;
	}
}

unittest
{
	writeln("Edit source/app.d to start your project.");

	TT tt;
	tt.ft = 0.1258f;
	tt.dt = DateTime(2015,2,15,10,25,30);

	TA ta;
	ta.data = [0x00,0x01,0x03,0x04,0x05];
	ta.str = "hello world";
	ta.db = 12.58;
	ta.lo = 897;
	ta.bl = false;
	ta.ui = 90;
	ta.ta = tt;
	ta.iarry = [0,1,2,3,4,5,6,7,8,9];

	TAT tat;
	tat.ta = ta;
	tat.tt = [TT(0.256f,DateTime(2015,2,15,10,25,30)),TT(1.256f,DateTime(2016,2,15,10,25,30)),TT(2.256f,DateTime(2017,2,15,10,25,30))];
	tat.ttt = new TT[][2];
	tat.ttt[0] = [TT(0.256f,DateTime(2015,2,15,10,25,30)),TT(0.356f,DateTime(2016,2,15,10,25,30)),TT(0.456f,DateTime(2017,2,15,10,25,30))];
	tat.ttt[1] = [TT(1.256f,DateTime(2018,2,15,10,25,30)),TT(1.356f,DateTime(2019,2,15,10,25,30)),TT(2.356f,DateTime(2020,3,15,10,25,30))];

    auto buffer = new Buffer!Mallocator();
    WriteStream strem = WriteStream(buffer);
	TA.serialize(ta,&strem);
    ubyte[] data = cast(ubyte[])(buffer.allData);
	writeln("sridata is : ", data);

	ReadStream steam = ReadStream(data);

	TA tta;
	writeln("TA.unSerialize");
	TA.unSerialize(&tta,&steam);

	assert(ta.data == tta.data);
	assert(ta.iarry ==  tta.iarry);
	assert(ta.str ==  tta.str);
	assert(ta.ta.ft ==  tta.ta.ft);
	assert(ta.ta.dt ==  tta.ta.dt);
	assert(ta.db ==  tta.db);
	assert(ta.ui ==  tta.ui);

	writeln("\n\n\n");

	import std.traits;
	string aaa;
	writeln("char is : ",is(ForeachType!(string) == char) );


	writeln("\n--------------------------\n");
	writeln("build fun: \n", _serializeFun!TT(), "\n\n-----------------------------");
	enum strin = _serializeFun!TAT();
	writeln("build fun: \n", strin, "\n\n-----------------------------");

	testTAT();
}

unittest
{
    TT2 tt2;
    tt2.ft = 0.1258f;
    tt2.dt = DateTime(2015,2,15,10,25,30);
    tt2.tt2 = 5000;

    auto buffer = new Buffer!Mallocator();
    WriteStream strem = WriteStream(buffer);
    TT2.serialize(tt2,&strem);
    ubyte[] data = cast(ubyte[])(buffer.allData);

    ReadStream steam = ReadStream(data);

    TT tt;
    writeln("TT.unSerialize");
    TT.unSerialize(&tt,&steam);

    assert(tt.ft == tt2.ft);
    assert(tt.dt == tt2.dt);
}
