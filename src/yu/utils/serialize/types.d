module yu.utils.serialize.types;

import yu.traits;
public import std.datetime;

/**
 *  数字有字节序，大端字节序
 *  时间和日期是内置的组合类型，顺序是固定的，其中占用2个byte的有字节序 （日期时间内置组合是因为其字段固定还比较常用，比自定义结构省去存储字段类型的空间）
 *
*/
enum Types : ubyte
{
	End 			= 0x00,
	//base type
	Char		= 0x01, // 1 byte
	UChar		= 0x02, // 1 byte
	Byte		= Char, // 1 byte
	UByte		= UChar,// 1 byte
	Bool 		= 0x03, // 1 byte
	Short  		= 0x04, // 2 byte
	UShort 		= 0x05, // 2 byte
	Int			= 0x06, // 4 byte
	UInt		= 0x07, // 4 byte
	Long		= 0x08, // 8 byte
	ULong		= 0x09, // 8 byte
	Float		= 0x0A, // 4 byte
	Double		= 0x0B, // 8 byte

	// 内置组合type
	// Time 序列化后布局： 00(时 1byte) 00（分 1byte） 00（秒 1byte） 00 00（毫秒 2byte）
	Time		= 0x0C, // 5 byte:  hour ,minute,second is ubyte, msecond is ushort
	// Date 序列化后布局： 00 00(年 2byte) 00（月 1byte） 00（日 1byte）
	Date		= 0x0D, // 4 byte: 1 2 是ushort year。 month and day is ubyte
	// DateTime 序列化后布局： 00 00(年 2byte) 00（月 1byte） 00（日 1byte） 00(时 1byte) 00（分 1byte） 00（秒 1byte）
	DateTime	= 0x0E, // 7 byte: 1 2 是ushort year。 month ，day， hour， minute, second is ubyte

	// 组合 type， 内容是其字段按照顺序分解为基本或者内置组合类型写入，不关心变量名，不保存顺序信息。
	Struct		= 0x0F,
	// 数组类型， 元素按照从0～$顺序写入,如果是多维数组也是一维一维的记录写入。
	Array		= 0x10,

//	Map			= 0x11, Not support
}

struct Time
{
	this(ubyte h, ubyte m, ubyte s = 0x00, ushort ms = 0) {
		hour = h;
		minute = m;
		second = s;
		msecond = ms;
	}

	ubyte hour;
	ubyte minute;
	ubyte second;
	ushort msecond;

	string toString(){
		import std.string;
		import std.format;
		return format("%d:%d:%d.%d",hour,minute,second,msecond);
	}
}

template isBasicSupport(T)
{
	enum isChar = is(T == char) || is(T == ubyte) || is(T == byte) ;
	enum isNum = (is(T == short) || is(T == ushort) || is(T == int) || is(T == uint) || is(T == long) || is(T == ulong) || is(T == double) || is(T == float));
	enum isDateTime = is(T == Date) || is(T == DateTime) || is(T == Time);
	static if(isArray!T && !is(T == string))
		enum isBSupport = isBasicSupport!(ForeachType!T).isBSupport;
	else
		enum isBSupport = is(T == bool) || isChar || isNum || isDateTime || is(T == string) || is(T == struct) ;
}

template isStruct(T)
{
	static if(isArray!T)
		enum isStruct = isStruct!(ForeachType!T);
	else
		enum isStruct =  is(T == struct) && !isBasicSupport!(T).isDateTime;
}

template dtTypes(T)
{
	static if(is(T == char) || is(T == byte))
		enum dtTypes = Types.Char;
	else static if(is(T == ubyte))
		enum dtTypes = Types.UByte;
	else static if(is(T == short))
		enum dtTypes = Types.Short;
	else static if(is(T == ushort))
		enum dtTypes = Types.UShort;
	else static if(is(T == int))
		enum dtTypes = Types.Int;
	else static if(is(T == uint))
		enum dtTypes = Types.UInt;
	else static if(is(T == long))
		enum dtTypes = Types.Long;
	else static if(is(T == ulong))
		enum dtTypes = Types.ULong;
	else static if(is(T == float))
		enum dtTypes = Types.Float;
	else static if(is(T == double))
		enum dtTypes = Types.Double;
	else static if(is(T == bool))
		enum dtTypes = Types.Bool;
	else static if(is(T == Date))
		enum dtTypes = Types.Date;
	else static if(is(T == Time))
		enum dtTypes = Types.Time;
	else static if(is(T == DateTime))
		enum dtTypes = Types.DateTime;
	else static if(is(T == struct))
		enum dtTypes = Types.Struct;
	else static if(isArray!T)
		enum dtTypes = Types.Array;
}
