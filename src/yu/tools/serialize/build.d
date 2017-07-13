module yu.tools.serialize.build;

import yu.traits;

public import yu.tools.serialize.write;
public import yu.tools.serialize.read;
public import yu.tools.serialize.types;
public import yu.tools.buffer;

mixin template Serialize(T) if(isStruct!T)
{
//	enum __buildStr__ = _serializeFun!T();
//    pragma(msg,__buildStr__);
	mixin(_serializeFun!T());

	pragma(inline)
	static IBuffer serialize(ref T value, IBuffer buffer)
	{
		WriteStream stream = WriteStream(buffer);
		serialize(value,&stream);
		return buffer;
	}

	pragma(inline)
	static T unsSerialize(ReadStream * stream)
	{
		T value;
		unSerialize(&value,stream);
		return value;
	}
}

string _serializeFun(T)() if(isStruct!T)
{
	string str = "static void serialize(ref " ~ T.stringof ~ " value, WriteStream * stream){\n";
	str ~= "stream.startStruct();\n scope(success) stream.endStruct();\n";

	string  rstr = "static void unSerialize(" ~ T.stringof ~ " * value, ReadStream * stream){\n";
	rstr ~= "stream.startReadStruct();\n scope(success) stream.endReadStruct();\n";

	foreach(memberName; FieldNameTuple!T)
	{
        alias CurrtType = typeof(__traits(getMember,T, memberName));
		static if(isBasicSupport!(CurrtType).isBSupport && !isCallable!(__traits(getMember,T, memberName)))
		{
			static if(isStruct!(CurrtType))
			{
				static if(isArray!(CurrtType))
				{
					str ~= writeStructArray!(CurrtType,"value." ~ memberName)();
                    rstr ~= readArray!(CurrtType,"value." ~ memberName)();
				}
				else
				{
					str ~= CurrtType.stringof ~ ".serialize(value." ~ memberName ~ ", stream);\n";
					rstr ~= CurrtType.stringof ~ ".unSerialize(&value." ~ memberName ~ ", stream);\n";
				}
			}
			else
			{
				str ~= "stream.write!(" ~ CurrtType.stringof ~ ")(" ~ "value." ~ memberName ~ ");\n";
                static if(isArray!(CurrtType) && !is(CurrtType == string))
                {
                    rstr ~= readArray!(CurrtType,"value." ~ memberName)();
                    //rstr ~= "stream.read!(" ~ CurrtType.stringof ~ ")((" ~ ForeachType!(CurrtType).stringof ~ " x){ value." ~ memberName ~ " ~= x;});\n";
                }
                else 
                {
				    rstr ~= "value." ~ memberName ~ " = stream.read!(" ~ CurrtType.stringof ~ ")();\n";
                }
			}
		}
	}
	str ~= "}\n";
	rstr ~= "}\n";
	return str ~ "\n" ~ rstr;
}

string writeStructArray(T,string memberName, int i = 0)()
{
	string str = "{stream.startArray!(";
	str ~= ForeachType!(T).stringof ~ ")();\n";
	str ~= "foreach(ref v"~ i.stringof ~" ; " ~ memberName ~ "){\n";
	static if(isArray!(ForeachType!T))
	{
		str ~= writeStructArray!(ForeachType!T,"v"~ i.stringof, i + 1)();
	}
	else
	{
		str ~= ForeachType!T.stringof ~ ".serialize(v"~ i.stringof ~ " ,stream);\n";
	}
	str ~= "}\n";
	str ~= "stream.endArray();}\n";
	return str;
}

string readArray(T,string memberName, int i = 0)()
{
	string  str = "{\n/*writeln(\"read array in : "~ memberName ~"\");*/\n ";
	str ~= "uint leng" ~ i.stringof ~ " = stream.startReadArray();\n";
//	str ~= "writeln(\"======\");\n ";
	str ~= memberName ~ " = new " ~ ForeachType!T.stringof ~ "[leng" ~  i.stringof ~ "];\n";
	str ~= "foreach(v"~ i.stringof ~" ; 0..leng" ~ i.stringof ~ "){\n";
	static if(isArray!(ForeachType!T))
	{
        str ~= readArray!(ForeachType!T,memberName ~"[v"~ i.stringof ~ "]", i + 1)();
	}
    else if(isStruct!(ForeachType!T))
	{
		str ~= ForeachType!T.stringof ~ ".unSerialize(&"~memberName ~ "[v"~ i.stringof ~ "] , stream);\n";
		
    } else {
        str ~= memberName ~ "[v"~ i.stringof ~ "] = stream.read!(" ~ ForeachType!T.stringof ~ ")();\n"; 
    }
	str ~= "}\n";
	str ~= "stream.endReadArray();\n}\n";
	return str;
}
