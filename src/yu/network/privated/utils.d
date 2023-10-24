module yu.network.privated.utils;

import yu.string;
import yu.container.string;

import yu.container.vector;
import std.string;
import std.algorithm;


String makeHwAddress(int len, ubyte *data)
{
	String result;
	for (int i = 0; i < len; ++i) {
        if (i){
			result ~= ':';
		}
		result ~= HexChar[(data[i] / 16)];
		result ~= HexChar[(data[i] % 16)];
    }
	return result;
}
