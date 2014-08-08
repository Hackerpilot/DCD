/**
 * This file is part of DCD, a development tool for the D programming language.
 * Copyright (C) 2014 Brian Schott
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

module actypes;

import std.algorithm;
import std.array;
import std.container;
//import std.stdio;
import std.typecons;
import std.allocator;

import containers.ttree;
import containers.unrolledlist;
import containers.slist;
import std.d.lexer;

import messages;
import string_interning;

/**
 * Any special information about a variable declaration symbol.
 */
enum SymbolQualifier : ubyte
{
	/// _none
	none,
	/// the symbol is an _array
	array,
	/// the symbol is a associative array
	assocArray,
	/// the symbol is a function or delegate pointer
	func
}

/**
 * Autocompletion symbol
 */
struct ACSymbol
{
public:

	@disable this();

	/**
	 * Params:
	 *     name = the symbol's name
	 */
	this(string name)
	{
		this.name = name is null ? name : internString(name);
	}

	/**
	 * Params:
	 *     name = the symbol's name
	 *     kind = the symbol's completion kind
	 */
	this(string name, CompletionKind kind)
	{
		this.name = name is null ? name : internString(name);
		this.kind = kind;
	}

	/**
	 * Params:
	 *     name = the symbol's name
	 *     kind = the symbol's completion kind
	 *     resolvedType = the resolved type of the symbol
	 */
	this(string name, CompletionKind kind, ACSymbol* type)
	{
		this.name = name is null ? name : internString(name);
		this.kind = kind;
		this.type = type;
	}

	int opCmp(ref const ACSymbol other) const
	{
		// Compare the pointers because the strings have been interned.
		// Identical strings MUST have the same address
		if (name.ptr < other.name.ptr)
			return -1;
		if (name.ptr > other.name.ptr)
			return 1;
		return 0;
	}

	/**
	 * Gets all parts whose name matches the given string.
	 */
	ACSymbol*[] getPartsByName(string name)
	{
		ACSymbol s = ACSymbol(name);
		auto er = parts.equalRange(&s);
		if (er.empty)
			return array(aliasThisParts.equalRange(&s));
		else
			return array(er);
	}

	/**
	 * Symbol's name
	 */
	string name;

	/**
	 * Symbols that compose this symbol, such as enum members, class variables,
	 * methods, etc.
	 */
	TTree!(ACSymbol*, true, "a < b", false) parts;

	/**
	 * Symbols included due to an alias this.
	 */
	TTree!(ACSymbol*, true, "a < b", false) aliasThisParts;

	/**
	 * Calltip to display if this is a function
	 */
	string callTip;

	/**
	 * Module containing the symbol.
	 */
	string symbolFile;

	/**
	 * Documentation for the symbol.
	 */
	string doc;

	/**
	 * The symbol that represents the type.
	 */
	ACSymbol* type;

	/**
	 * Symbol location
	 */
	size_t location;

	/**
	 * The kind of symbol
	 */
	CompletionKind kind;

	/**
	 * Symbol qualifier
	 */
	SymbolQualifier qualifier;
}

/**
 * Contains symbols and supports lookup of symbols by cursor position.
 */
struct Scope
{
	/**
	 * Params:
	 *     begin = the beginning byte index
	 *     end = the ending byte index
	 */
	this (size_t begin, size_t end)
	{
		this.startLocation = begin;
		this.endLocation = end;
	}

	~this()
	{
		foreach (info; importInformation[])
			typeid(ImportInformation).destroy(info);
		foreach (child; children[])
			typeid(Scope).destroy(child);
	}

	/**
	 * Params:
	 *     cursorPosition = the cursor position in bytes
	 * Returns:
	 *     the innermost scope that contains the given cursor position
	 */
	Scope* getScopeByCursor(size_t cursorPosition)
	{
		if (cursorPosition < startLocation) return null;
		if (cursorPosition > endLocation) return null;
		foreach (child; children[])
		{
			auto childScope = child.getScopeByCursor(cursorPosition);
			if (childScope !is null)
				return childScope;
		}
		return cast(typeof(return)) &this;
	}

	/**
	 * Params:
	 *     cursorPosition = the cursor position in bytes
	 * Returns:
	 *     all symbols in the scope containing the cursor position, as well as
	 *     the symbols in parent scopes of that scope.
	 */
	ACSymbol*[] getSymbolsInCursorScope(size_t cursorPosition)
	{
		auto s = getScopeByCursor(cursorPosition);
		if (s is null)
			return [];
		UnrolledList!(ACSymbol*) symbols;
		symbols.insert(s.symbols[]);
		Scope* sc = s.parent;
		while (sc !is null)
		{
			symbols.insert(sc.symbols[]);
			sc = sc.parent;
		}
		return array(symbols[]);
	}

	/**
	 * Params:
	 *     name = the symbol name to search for
	 * Returns:
	 *     all symbols in this scope or parent scopes with the given name
	 */
	ACSymbol*[] getSymbolsByName(string name)
	{
		import std.range;
		ACSymbol s = ACSymbol(name);
		auto er = symbols.equalRange(&s);
		if (!er.empty)
			return cast(typeof(return)) array(er);
		if (parent is null)
			return [];
		return parent.getSymbolsByName(name);
	}

	/**
	 * Params:
	 *     name = the symbol name to search for
	 *     cursorPosition = the cursor position in bytes
	 * Returns:
	 *     all symbols with the given name in the scope containing the cursor
	 *     and its parent scopes
	 */
	ACSymbol*[] getSymbolsByNameAndCursor(string name, size_t cursorPosition)
	{
		auto s = getScopeByCursor(cursorPosition);
		if (s is null)
			return [];
		return s.getSymbolsByName(name);
	}

	ACSymbol*[] getSymbolsAtGlobalScope(string name)
	{
		if (parent !is null)
			return parent.getSymbolsAtGlobalScope(name);
		return getSymbolsByName(name);
	}

	/// Imports contained in this scope
	UnrolledList!(ImportInformation*) importInformation;

	/// The scope that contains this one
	Scope* parent;

	/// Child scopes
	UnrolledList!(Scope*, false) children;

	/// Start location of this scope in bytes
	size_t startLocation;

	/// End location of this scope in bytes
	size_t endLocation;

	/// Symbols contained in this scope
	TTree!(ACSymbol*, true, "a < b", false) symbols;
}

/**
 * Import information
 */
struct ImportInformation
{
	/// Import statement parts
	UnrolledList!string importParts;
	/// module relative path
	string modulePath;
	/// symbols to import from this module
	UnrolledList!(Tuple!(string, string), false) importedSymbols;
	/// true if the import is public
	bool isPublic;
}


/**
 * Symbols for the built in types
 */
TTree!(ACSymbol*, true, "a < b", false) builtinSymbols;

/**
 * Array properties
 */
TTree!(ACSymbol*, true, "a < b", false) arraySymbols;

/**
 * Associative array properties
 */
TTree!(ACSymbol*, true, "a < b", false) assocArraySymbols;

/**
 * Struct, enum, union, class, and interface properties
 */
TTree!(ACSymbol*, true, "a < b", false) aggregateSymbols;

/**
 * Class properties
 */
TTree!(ACSymbol*, true, "a < b", false) classSymbols;

private immutable(string[24]) builtinTypeNames;

string getBuiltinTypeName(IdType id)
{
	switch (id)
	{
	case tok!"int": return builtinTypeNames[0];
	case tok!"uint": return builtinTypeNames[1];
	case tok!"double": return builtinTypeNames[2];
	case tok!"idouble": return builtinTypeNames[3];
	case tok!"float": return builtinTypeNames[4];
	case tok!"ifloat": return builtinTypeNames[5];
	case tok!"short": return builtinTypeNames[6];
	case tok!"ushort": return builtinTypeNames[7];
	case tok!"long": return builtinTypeNames[8];
	case tok!"ulong": return builtinTypeNames[9];
	case tok!"char": return builtinTypeNames[10];
	case tok!"wchar": return builtinTypeNames[11];
	case tok!"dchar": return builtinTypeNames[12];
	case tok!"bool": return builtinTypeNames[13];
	case tok!"void": return builtinTypeNames[14];
	case tok!"cent": return builtinTypeNames[15];
	case tok!"ucent": return builtinTypeNames[16];
	case tok!"real": return builtinTypeNames[17];
	case tok!"ireal": return builtinTypeNames[18];
	case tok!"byte": return builtinTypeNames[19];
	case tok!"ubyte": return builtinTypeNames[20];
	case tok!"cdouble": return builtinTypeNames[21];
	case tok!"cfloat": return builtinTypeNames[22];
	case tok!"creal": return builtinTypeNames[23];
	default: assert (false);
	}
}


/**
 * Initializes builtin types and the various properties of builtin types
 */
static this()
{
	builtinTypeNames[0] = internString("int");
	builtinTypeNames[1] = internString("uint");
	builtinTypeNames[2] = internString("double");
	builtinTypeNames[3] = internString("idouble");
	builtinTypeNames[4] = internString("float");
	builtinTypeNames[5] = internString("ifloat");
	builtinTypeNames[6] = internString("short");
	builtinTypeNames[7] = internString("ushort");
	builtinTypeNames[8] = internString("long");
	builtinTypeNames[9] = internString("ulong");
	builtinTypeNames[10] = internString("char");
	builtinTypeNames[11] = internString("wchar");
	builtinTypeNames[12] = internString("dchar");
	builtinTypeNames[13] = internString("bool");
	builtinTypeNames[14] = internString("void");
	builtinTypeNames[15] = internString("cent");
	builtinTypeNames[16] = internString("ucent");
	builtinTypeNames[17] = internString("real");
	builtinTypeNames[18] = internString("ireal");
	builtinTypeNames[19] = internString("byte");
	builtinTypeNames[20] = internString("ubyte");
	builtinTypeNames[21] = internString("cdouble");
	builtinTypeNames[22] = internString("cfloat");
	builtinTypeNames[23] = internString("creal");


	auto bool_ = allocate!ACSymbol(Mallocator.it, "bool", CompletionKind.keyword);
	auto int_ = allocate!ACSymbol(Mallocator.it, "int", CompletionKind.keyword);
	auto long_ = allocate!ACSymbol(Mallocator.it, "long", CompletionKind.keyword);
	auto byte_ = allocate!ACSymbol(Mallocator.it, "byte", CompletionKind.keyword);
	auto char_ = allocate!ACSymbol(Mallocator.it, "char", CompletionKind.keyword);
	auto dchar_ = allocate!ACSymbol(Mallocator.it, "dchar", CompletionKind.keyword);
	auto short_ = allocate!ACSymbol(Mallocator.it, "short", CompletionKind.keyword);
	auto ubyte_ = allocate!ACSymbol(Mallocator.it, "ubyte", CompletionKind.keyword);
	auto uint_ = allocate!ACSymbol(Mallocator.it, "uint", CompletionKind.keyword);
	auto ulong_ = allocate!ACSymbol(Mallocator.it, "ulong", CompletionKind.keyword);
	auto ushort_ = allocate!ACSymbol(Mallocator.it, "ushort", CompletionKind.keyword);
	auto wchar_ = allocate!ACSymbol(Mallocator.it, "wchar", CompletionKind.keyword);

	auto alignof_ = allocate!ACSymbol(Mallocator.it, "alignof", CompletionKind.keyword);
	auto mangleof_ = allocate!ACSymbol(Mallocator.it, "mangleof", CompletionKind.keyword);
	auto sizeof_ = allocate!ACSymbol(Mallocator.it, "sizeof", CompletionKind.keyword);
	auto stringof_ = allocate!ACSymbol(Mallocator.it, "init", CompletionKind.keyword);
	auto init = allocate!ACSymbol(Mallocator.it, "stringof", CompletionKind.keyword);

	arraySymbols.insert(alignof_);
	arraySymbols.insert(allocate!ACSymbol(Mallocator.it, "dup", CompletionKind.keyword));
	arraySymbols.insert(allocate!ACSymbol(Mallocator.it, "idup", CompletionKind.keyword));
	arraySymbols.insert(init);
	arraySymbols.insert(allocate!ACSymbol(Mallocator.it, "length", CompletionKind.keyword, ulong_));
	arraySymbols.insert(mangleof_);
	arraySymbols.insert(allocate!ACSymbol(Mallocator.it, "ptr", CompletionKind.keyword));
	arraySymbols.insert(allocate!ACSymbol(Mallocator.it, "reverse", CompletionKind.keyword));
	arraySymbols.insert(sizeof_);
	arraySymbols.insert(allocate!ACSymbol(Mallocator.it, "sort", CompletionKind.keyword));
	arraySymbols.insert(stringof_);

	assocArraySymbols.insert(alignof_);
	assocArraySymbols.insert(allocate!ACSymbol(Mallocator.it, "byKey", CompletionKind.keyword));
	assocArraySymbols.insert(allocate!ACSymbol(Mallocator.it, "byValue", CompletionKind.keyword));
	assocArraySymbols.insert(allocate!ACSymbol(Mallocator.it, "dup", CompletionKind.keyword));
	assocArraySymbols.insert(allocate!ACSymbol(Mallocator.it, "get", CompletionKind.keyword));
	assocArraySymbols.insert(allocate!ACSymbol(Mallocator.it, "init", CompletionKind.keyword));
	assocArraySymbols.insert(allocate!ACSymbol(Mallocator.it, "keys", CompletionKind.keyword));
	assocArraySymbols.insert(allocate!ACSymbol(Mallocator.it, "length", CompletionKind.keyword, ulong_));
	assocArraySymbols.insert(mangleof_);
	assocArraySymbols.insert(allocate!ACSymbol(Mallocator.it, "rehash", CompletionKind.keyword));
	assocArraySymbols.insert(sizeof_);
	assocArraySymbols.insert(stringof_);
	assocArraySymbols.insert(init);
	assocArraySymbols.insert(allocate!ACSymbol(Mallocator.it, "values", CompletionKind.keyword));

	ACSymbol*[11] integralTypeArray;
	integralTypeArray[0] = bool_;
	integralTypeArray[1] = int_;
	integralTypeArray[2] = long_;
	integralTypeArray[3] = byte_;
	integralTypeArray[4] = char_;
	integralTypeArray[4] = dchar_;
	integralTypeArray[5] = short_;
	integralTypeArray[6] = ubyte_;
	integralTypeArray[7] = uint_;
	integralTypeArray[8] = ulong_;
	integralTypeArray[9] = ushort_;
	integralTypeArray[10] = wchar_;

	foreach (s; integralTypeArray)
	{
		s.parts.insert(allocate!ACSymbol(Mallocator.it, "init", CompletionKind.keyword, s));
		s.parts.insert(allocate!ACSymbol(Mallocator.it, "min", CompletionKind.keyword, s));
		s.parts.insert(allocate!ACSymbol(Mallocator.it, "max", CompletionKind.keyword, s));
		s.parts.insert(alignof_);
		s.parts.insert(sizeof_);
		s.parts.insert(stringof_);
		s.parts.insert(mangleof_);
		s.parts.insert(init);
	}

	auto cdouble_ = allocate!ACSymbol(Mallocator.it, "cdouble", CompletionKind.keyword);
	auto cent_ = allocate!ACSymbol(Mallocator.it, "cent", CompletionKind.keyword);
	auto cfloat_ = allocate!ACSymbol(Mallocator.it, "cfloat", CompletionKind.keyword);
	auto creal_ = allocate!ACSymbol(Mallocator.it, "creal", CompletionKind.keyword);
	auto double_ = allocate!ACSymbol(Mallocator.it, "double", CompletionKind.keyword);
	auto float_ = allocate!ACSymbol(Mallocator.it, "float", CompletionKind.keyword);
	auto idouble_ = allocate!ACSymbol(Mallocator.it, "idouble", CompletionKind.keyword);
	auto ifloat_ = allocate!ACSymbol(Mallocator.it, "ifloat", CompletionKind.keyword);
	auto ireal_ = allocate!ACSymbol(Mallocator.it, "ireal", CompletionKind.keyword);
	auto real_ = allocate!ACSymbol(Mallocator.it, "real", CompletionKind.keyword);
	auto ucent_ = allocate!ACSymbol(Mallocator.it, "ucent", CompletionKind.keyword);

	ACSymbol*[11] floatTypeArray;
	floatTypeArray[0] = cdouble_;
	floatTypeArray[1] = cent_;
	floatTypeArray[2] = cfloat_;
	floatTypeArray[3] = creal_;
	floatTypeArray[4] = double_;
	floatTypeArray[5] = float_;
	floatTypeArray[6] = idouble_;
	floatTypeArray[7] = ifloat_;
	floatTypeArray[8] = ireal_;
	floatTypeArray[9] = real_;
	floatTypeArray[10] = ucent_;

	foreach (s; floatTypeArray)
	{
		s.parts.insert(alignof_);
		s.parts.insert(allocate!ACSymbol(Mallocator.it, "dig", CompletionKind.keyword, s));
		s.parts.insert(allocate!ACSymbol(Mallocator.it, "epsilon", CompletionKind.keyword, s));
		s.parts.insert(allocate!ACSymbol(Mallocator.it, "infinity", CompletionKind.keyword, s));
		s.parts.insert(allocate!ACSymbol(Mallocator.it, "init", CompletionKind.keyword, s));
		s.parts.insert(mangleof_);
		s.parts.insert(allocate!ACSymbol(Mallocator.it, "mant_dig", CompletionKind.keyword, int_));
		s.parts.insert(allocate!ACSymbol(Mallocator.it, "max", CompletionKind.keyword, s));
		s.parts.insert(allocate!ACSymbol(Mallocator.it, "max_10_exp", CompletionKind.keyword, int_));
		s.parts.insert(allocate!ACSymbol(Mallocator.it, "max_exp", CompletionKind.keyword, int_));
		s.parts.insert(allocate!ACSymbol(Mallocator.it, "min", CompletionKind.keyword, s));
		s.parts.insert(allocate!ACSymbol(Mallocator.it, "min_exp", CompletionKind.keyword, int_));
		s.parts.insert(allocate!ACSymbol(Mallocator.it, "min_10_exp", CompletionKind.keyword, int_));
		s.parts.insert(allocate!ACSymbol(Mallocator.it, "min_normal", CompletionKind.keyword, s));
		s.parts.insert(allocate!ACSymbol(Mallocator.it, "nan", CompletionKind.keyword, s));
		s.parts.insert(sizeof_);
		s.parts.insert(stringof_);
	}

	aggregateSymbols.insert(allocate!ACSymbol(Mallocator.it, "tupleof", CompletionKind.keyword));
	aggregateSymbols.insert(mangleof_);
	aggregateSymbols.insert(alignof_);
	aggregateSymbols.insert(sizeof_);
	aggregateSymbols.insert(stringof_);
	aggregateSymbols.insert(init);

	classSymbols.insert(allocate!ACSymbol(Mallocator.it, "classInfo", CompletionKind.variableName));
	classSymbols.insert(allocate!ACSymbol(Mallocator.it, "tupleof", CompletionKind.variableName));
	classSymbols.insert(allocate!ACSymbol(Mallocator.it, "__vptr", CompletionKind.variableName));
	classSymbols.insert(allocate!ACSymbol(Mallocator.it, "__monitor", CompletionKind.variableName));
	classSymbols.insert(mangleof_);
	classSymbols.insert(alignof_);
	classSymbols.insert(sizeof_);
	classSymbols.insert(stringof_);
	classSymbols.insert(init);

	ireal_.parts.insert(allocate!ACSymbol(Mallocator.it, "im", CompletionKind.keyword, real_));
	ifloat_.parts.insert(allocate!ACSymbol(Mallocator.it, "im", CompletionKind.keyword, float_));
	idouble_.parts.insert(allocate!ACSymbol(Mallocator.it, "im", CompletionKind.keyword, double_));
	ireal_.parts.insert(allocate!ACSymbol(Mallocator.it, "re", CompletionKind.keyword, real_));
	ifloat_.parts.insert(allocate!ACSymbol(Mallocator.it, "re", CompletionKind.keyword, float_));
	idouble_.parts.insert(allocate!ACSymbol(Mallocator.it, "re", CompletionKind.keyword, double_));

	auto void_ = allocate!ACSymbol(Mallocator.it, "void", CompletionKind.keyword);

	builtinSymbols.insert(bool_);
	bool_.type = bool_;
	builtinSymbols.insert(int_);
	int_.type = int_;
	builtinSymbols.insert(long_);
	long_.type = long_;
	builtinSymbols.insert(byte_);
	byte_.type = byte_;
	builtinSymbols.insert(char_);
	char_.type = char_;
	builtinSymbols.insert(dchar_);
	dchar_.type = dchar_;
	builtinSymbols.insert(short_);
	short_.type = short_;
	builtinSymbols.insert(ubyte_);
	ubyte_.type = ubyte_;
	builtinSymbols.insert(uint_);
	uint_.type = uint_;
	builtinSymbols.insert(ulong_);
	ulong_.type = ulong_;
	builtinSymbols.insert(ushort_);
	ushort_.type = ushort_;
	builtinSymbols.insert(wchar_);
	wchar_.type = wchar_;
	builtinSymbols.insert(cdouble_);
	cdouble_.type = cdouble_;
	builtinSymbols.insert(cent_);
	cent_.type = cent_;
	builtinSymbols.insert(cfloat_);
	cfloat_.type = cfloat_;
	builtinSymbols.insert(creal_);
	creal_.type = creal_;
	builtinSymbols.insert(double_);
	double_.type = double_;
	builtinSymbols.insert(float_);
	float_.type = float_;
	builtinSymbols.insert(idouble_);
	idouble_.type = idouble_;
	builtinSymbols.insert(ifloat_);
	ifloat_.type = ifloat_;
	builtinSymbols.insert(ireal_);
	ireal_.type = ireal_;
	builtinSymbols.insert(real_);
	real_.type = real_;
	builtinSymbols.insert(ucent_);
	ucent_.type = ucent_;
	builtinSymbols.insert(void_);
	void_.type = void_;

//	writeln(">>Builtin symbols");
//	foreach (symbol; builtinSymbols[])
//		writeln(symbol.name, " ", symbol.name.ptr);
//	writeln("<<Builtin symbols");
}

