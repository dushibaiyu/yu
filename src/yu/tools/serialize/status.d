module yu.tools.serialize.status;

import yu.tools.serialize.types;
@trusted :
enum Status
{
	InStruct,
	InArray,
	None
}

struct StatusNode
{
	Status state;
	size_t begin;
	uint   len;
	
	Types 	type;
private:
	StatusNode * next;
}


struct StatusStack
{
	StatusNode * front()
	{
		return _top;
	}
	
	void push(StatusNode * node)
	{
		node.next = _top;
		_top = node;
	}
	
	StatusNode * pop()
	{
		StatusNode * node = null;
		if(_top !is null)
		{ 
			node = _top;
			_top = node.next;
		}
		return node;
	}
	
private:
	StatusNode * _top = null;
}