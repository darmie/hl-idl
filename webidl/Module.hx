package webidl;

#if macro
import webidl.Data;
import haxe.macro.Context;
import haxe.macro.Expr;

class Module {
	var p : Position;
	var hl : Bool;
	var pack : Array<String>;
	var opts : Options;
	var types : Array<TypeDefinition> = [];
	var typeNames = new Map();

	function new(p, pack, hl, opts) {
		this.p = p;
		this.pack = pack;
		this.hl = hl;
		this.opts = opts;
	}

	function makeName( name : String ) {
		// name - list of comma separated prefixes
		if( opts.chopPrefix != null ) {
			var prefixes = opts.chopPrefix.split(',');
			for (prefix in prefixes) {
				if (StringTools.startsWith(name, prefix)) {
					name = name.substr(prefix.length);
				}
			}
		}
		return capitalize(name);
	}

	function buildModule( decls : Array<Definition> ) {
		for( d in decls )
			buildDecl(d);
		return types;
	}

	function makeVectorType( t : TypeAttr, vt : Type, vdim : Int, isReturn:Bool ): ComplexType {
		return switch(vt) {
			case TFloat: 
				switch(vdim) {
					case 2: macro : Vec2;
					case 3: macro : Vec3;
					case 4: macro : Vec4;
					default: throw "Unsupported vector dimension" + vdim;
				}
			case TInt:   
				switch(vdim) {
					case 2: macro : Int2;
					case 3: macro : Int3;
					case 4: macro : Int4;
					default: throw "Unsupported vector dimension" + vdim;
				}
			case TDouble:
				switch(vdim) {
					case 2: macro : Float2;
					case 3: macro : Float3;
					case 4: macro : Float4;
					default: throw "Unsupported vector dimension" + vdim;
				}
	
			default: throw "Unsupported vector type " + vt;
		};
	}
	function makeType( t : TypeAttr,isReturn:Bool ) : ComplexType {
		return switch( t.t ) {
		case TVoid: macro : Void;
		case TChar: macro : hl.UI8;
		case TInt, TUInt: (t.attr.contains(AOut)) ? macro : hl.Ref<Int> : macro : Int;
		case TInt64 : hl ? macro : hl.I64 : macro : haxe.Int64; 
		case TShort: hl ? macro : hl.UI16 : macro : Int;
		case TFloat: hl ? macro : Single : macro : Float;
		case TDouble: macro : Float;
		case TBool: macro : Bool;
		case THString : isReturn && false? macro : hl.Bytes : macro : String;
		case TAny: macro : webidl.Types.Any;
		case TEnum(_): macro : Int;
		case TBytes: macro : hl.Bytes;
		case TVector(vt, vdim): makeVectorType( t, vt, vdim, isReturn);
		case TPointer(pt):
			switch(pt) {
				case TChar: macro : hl.BytesAccess<hl.UI8>;
				case TInt, TUInt: macro :  hl.BytesAccess<Int>;
				case TFloat:  macro : hl.BytesAccess<Single>;
				case TDouble: macro :  hl.BytesAccess<Float>;
				case TBool: macro : hl.BytesAccess<Bool>;
				case TShort:  macro : hl.BytesAccess<hl.UI16>;
				default:
					throw "Unsupported array type. Sorry";
			}
		case TArray(at, _):
			switch(at) {
				case TChar: macro : hl.NativeArray<hl.UI8>;
				case TInt: macro : hl.NativeArray<Int>;
				case TFloat:  macro : hl.NativeArray<Single>;
				case TDouble: macro : hl.NativeArray<Float>;
				case TBool: macro : hl.NativeArray<Bool>;
				case TShort:  macro : hl.NativeArray<hl.UI16>;
				default:
					throw "Unsupported array type. Sorry";
			}
//			var tt = makeType({ t : t, attr : [] });
//			macro : webidl.Types.NativePtr<$tt>;
		case TVoidPtr: macro : webidl.Types.VoidPtr;
		case TCustom(id): 
			if (typeNames.exists(id)) {
				TPath( typeNames[id]);
			}
			else
				TPath({ pack : [], name : makeName(id) });
		}
	}

	function defVal( t : TypeAttr ) : Expr {
		return switch( t.t ) {
		case TVoid: throw "assert";
		case TInt, TUInt, TShort, TInt64, TChar: { expr : EConst(CInt("0")), pos : p };
		case TFloat, TDouble: { expr : EConst(CFloat("0.")), pos : p };
		case TBool: { expr : EConst(CIdent("false")), pos : p };
		case TCustom(id):
			var ex = { expr : EConst(CInt("0")), pos : p };
			var tp = TPath({ pack : [], name : id });

			if (typeNames.exists(id))  
				{ expr : ECast(ex, tp), pos : p };
			else
				{ expr : EConst(CIdent("null")), pos : p };
		default: 
			{ expr : EConst(CIdent("null")), pos : p };
		}
	}

	function makeNative( name : String ) : MetadataEntry {
		return { name : ":hlNative", params : [{ expr : EConst(CString(opts.nativeLib)), pos : p },{ expr : EConst(CString(name)), pos : p }], pos : p };
	}

	function makeEither( arr : Array<ComplexType> ) {
		var i = 0;
		var t = arr[i++];
		while( i < arr.length ) {
			var t2 = arr[i++];
			t = TPath({ pack : ["haxe", "extern"], name : "EitherType", params : [TPType(t), TPType(t2)] });
		}
		return t;
	}

	function makePosition( pos : webidl.Data.Position ) {
		if( pos == null )
			return p;
		return Context.makePosition({ min : pos.pos, max : pos.pos + 1, file : pos.file });
	}

	function makeNativeFieldRaw( iname : String, fname : String, pos : Position, args : Array<FArg>, ret : TypeAttr, pub : Bool ) : Field {
		var name = fname;
		var isConstr = name == iname;
		if( isConstr ) {
			name = "new";
			ret = { t : TCustom(iname), attr : [] };
		}

		var expr = if( ret.t == TVoid )
			{ expr : EBlock([]), pos : p };
		else
			{ expr : EReturn(defVal(ret)), pos : p };

		var access : Array<Access> = [];
		if( !hl ) access.push(AInline);
		if( pub ) access.push(APublic);
		if( isConstr ) access.push(AStatic);
		if (ret.attr.contains(AStatic)) {
			access.push(AStatic);
		}

		var x =
		 {
			pos : pos,
			name : pub ? name : name + args.length,
			meta : [makeNative(iname+"_" + name + (name == "delete" ? "" : ""+args.length))],
			access : access,
			kind : FFun({
				ret : makeType(ret, true),
				expr : expr,
				args : [for( a in args ) {

					//This pattern is brutallly bad There must be a cleaner way to do this
					var sub = false;
					for(aattr in a.t.attr) {
						switch(aattr) {
								case ASubstitute(_): 
								sub = true;
								break;
							default: 
						}
					}
					if (a.t.attr.contains(AReturn) || sub) {continue;}
					{ name : a.name, opt : a.opt, type : makeType(a.t, false) }}],
			}),
		};

		
		return x;
	}

	function makeNativeField( iname : String, f : webidl.Data.Field, args : Array<FArg>, ret : TypeAttr, pub : Bool ) : Field {
		return makeNativeFieldRaw(iname, f.name, makePosition(f.pos), args, ret, pub);
	}

	function filterArgs( args : Array<FArg>) {
		var b : Array<FArg> = [];

		for(a in args) {
			var skip = false;
			for (at in a.t.attr) {
				switch(at) {
					case AVirtual: skip = true;
					default:
				}
			}
			if (!skip) 
				b.push(a);
		}
		return b;
	}
	function buildDecl( d : Definition ) {
		var p = makePosition(d.pos);
		switch( d.kind ) {
		case DInterface(iname, attrs, fields):
			var dfields : Array<Field> = [];

			var variants = new Map();
			function getVariants( name : String ) {
				if( variants.exists(name) )
					return null;
				variants.set(name, true);
				var fl = [];
				for( f in fields )
					if( f.name == name )
						switch( f.kind ) {
						case FMethod(args, ret):
							fl.push({args:filterArgs(args), ret:ret,pos:f.pos});
						default:
						}
				return fl;
			}


			for( f in fields ) {
				switch( f.kind ) {
				case FMethod(_):
					var vars = getVariants(f.name);
					if( vars == null ) continue;

					var isConstr = f.name == iname;

					if( vars.length == 1 && !isConstr ) {

						var f = makeNativeField(iname, f, vars[0].args, vars[0].ret, true);
						dfields.push(f);
					} else { 
						// create dispatching code
						var maxArgs = 0;
						for( v in vars ) if( v.args.length > maxArgs ) maxArgs = v.args.length;

						if( vars.length > 1 && maxArgs == 0 )
							Context.error("Duplicate method declaration", makePosition(vars.pop().pos));

						var targs : Array<FunctionArg> = [];
						var argsTypes = [];
						for( i in 0...maxArgs ) {
							var types : Array<{t:TypeAttr,sign:String}>= [];
							var names = [];
							var opt = false;
							for( v in vars ) {
								var a = v.args[i];
								if( a == null ) {
									opt = true;
									continue;
								}
								var sign = haxe.Serializer.run(a.t);
								var found = false;
								for( t in types )
									if( t.sign == sign ) {
										found = true;
										break;
									}
								if( !found ) types.push({ t : a.t, sign : sign });
								if( names.indexOf(a.name) < 0 )
									names.push(a.name);
								if( a.opt )
									opt = true;
							}
							argsTypes.push(types);
							targs.push({
								name : names.join("_"),
								opt : opt,
								type : makeEither([for( t in types ) makeType(t.t, false)]),
							});
						}

						// native impls
						var retTypes : Array<{t:TypeAttr,sign:String}> = [];
						for( v in vars ) {
							var f = makeNativeField(iname, f, v.args, v.ret, false );

							var sign = haxe.Serializer.run(v.ret);
							var found = false;
							for( t in retTypes )
								if( t.sign == sign ) {
									found = true;
									break;
								}
							if( !found ) retTypes.push({ t : v.ret, sign : sign });

							dfields.push(f);
						}

						vars.sort(function(v1, v2) return v1.args.length - v2.args.length);

						// dispatch only on args count
						function makeCall( v : { args : Array<FArg>, ret : TypeAttr } ) : Expr {
							var ident = { expr : EConst(CIdent( (f.name == iname ? "new" : f.name) + v.args.length )), pos : p};
							var e : Expr = { expr : ECall(ident, [for( i in 0...v.args.length ) { expr : ECast({ expr : EConst(CIdent(targs[i].name)), pos : p }, null), pos : p }]), pos : p };
							if( v.ret.t != TVoid )
								e = { expr : EReturn(e), pos : p };
							else if( isConstr )
								e = macro this = $e;
							return e;
						}

						var expr = makeCall(vars[vars.length - 1]);
						for( i in 1...vars.length ) {
							var v = vars[vars.length - 1 - i];
							var aname = targs[v.args.length].name;
							var call = makeCall(v);
							expr = macro if( $i{aname} == null ) $call else $expr;
						}

						dfields.push({
							name : isConstr ? "new" : f.name,
							pos : makePosition(f.pos),
							access : [APublic, AInline],
							kind : FFun({
								expr : expr,
								args : targs,
								ret : makeEither([for( t in retTypes ) makeType(t.t, false)]),
							}),
						});


					}


				case FAttribute(t):
					var tt = makeType(t, false);
					dfields.push({
						pos : p,
						name : f.name,
						kind : FProp("get", "set", tt),
						access : [APublic],
					});
					dfields.push({
						pos : p,
						name : "get_" + f.name,
						meta : [makeNative(iname+"_get_" + f.name)],
						kind : FFun({
							ret : makeType(t, true),
							expr : macro return ${defVal(t)},
							args : [],
						}),
					});
					dfields.push({
						pos : p,
						name : "set_" + f.name,
						meta : [makeNative(iname+"_set_" + f.name)],
						kind : FFun({
							ret : tt,
							expr : macro return ${defVal(t)},
							args : [{ name : "_v", type : tt }],
						}),
					});
					
					var vt : Type = null;
					var vta : TypeAttr = null;
					var vdim = 0;

					var isVector = switch(t.t) {
						case TVector(vvt, vvdim): vt = vvt; vdim = vvdim; vta = {t: vt, attr: t.attr}; true;
						default:false;
					}

					if (isVector && false) {
						dfields.push({
							pos : p,
							name : "set" + f.name + vdim,
							meta : [makeNative(iname+"_set" + f.name + vdim)],
							access : [APublic, AInline],
							kind : FFun({
								ret : macro : Void,
								expr : macro return,
								args :[for (c in 0...vdim) { name : "_v" + c, type : makeType(vta, false) } ],
						}),
					});
					}

				case DConst(name, type, value):
					dfields.push({
						pos : p,
						name : name,
						access : [APublic, AStatic, AInline],
						kind : FVar(
							makeType({t : type, attr : []}, false),
							macro $i{value}
						)
					});
				}
			}
			var td : TypeDefinition = {
				pos : p,
				pack : pack,
				name : makeName(iname),
				meta : [],
				kind : TDAbstract(macro : webidl.Types.Ref, [], [macro : webidl.Types.Ref]),
				fields : dfields,
			};

			if( attrs.indexOf(ANoDelete) < 0 ) {
				dfields.push(makeNativeField(iname, { name : "delete", pos : null, kind : null }, [], { t : TVoid, attr : [] }, true));
			}

			if( !hl ) {
				for( f in dfields )
					if( f.meta != null )
						for( m in f.meta )
							if( m.name == ":hlNative" ) {
								if( f.access == null ) f.access = [];
								switch( f.kind ) {
								case FFun(df):
									var call = opts.nativeLib + "._eb_" + switch( m.params[1].expr ) { case EConst(CString(name)): name; default: throw "!"; };
									var args : Array<Expr> = [for( a in df.args ) { expr : EConst(CIdent(a.name)), pos : p }];
									if( f.access.contains(AStatic) ) {
										args.unshift(macro this);
									}
									df.expr = macro return untyped $i{call}($a{args});
								default: throw "assert";
								}
								if (f.access.indexOf(AInline) == -1) f.access.push(AInline);
								f.meta.remove(m);
								break;
							}
			}

			types.push(td);
		case DImplements(name,intf):
			var name = makeName(name);
			var intf = makeName(intf);
			var found = false;
			for( t in types )
				if( t.name == name ) {
					found = true;
					switch( t.kind ) {
					case TDAbstract(a, _):
						t.fields.push({
							pos : p,
							name : "_to" + intf,
							meta : [{ name : ":to", pos : p }],
							access : [AInline],
							kind : FFun({
								args : [],
								expr : macro return cast this,
								ret : TPath({ pack : [], name : intf }),
							}),
						});

						var toImpl = [intf];
						while( toImpl.length > 0 ) {
							var intf = toImpl.pop();
							var td = null;
							for( t2 in types ) {
								if( t2.name == intf )
									switch( t2.kind ) {
									case TDAbstract(a2, _, to):
										for ( inheritedField in t2.fields ) {
											// Search for existing field
											var fieldExists = false;
											for ( existingField in t.fields ) {
												if ( inheritedField.name == existingField.name ) {
													fieldExists = true;
													break;
												}
											}

											if ( !fieldExists ) {
												t.fields.push(inheritedField);
											}
										}
									default:
									}
							}
						}


					default:
						Context.warning("Cannot have " + name+" extends " + intf, p);
					}
					break;
				}
			if( !found )
				Context.warning("Class " + name+" not found for implements " + intf, p);
		case DEnum(name, attrs, values):
			var index = 0;
			var cfields = [for( v in values ) { pos : p, name : v, kind : FVar(null,{ expr : EConst(CInt(""+(index++))), pos : p }) }];

			// Add Int Conversion
			var ta : TypeAttr = { t : TInt, attr : [] };
			var toInt = makeNativeFieldRaw( name, "indexToValue", p, [], ta,true );
			cfields.push(toInt);

			toInt = makeNativeFieldRaw( name, "valueToIndex", p, [], ta,true );
			cfields.push(toInt);

			toInt = makeNativeFieldRaw( name, "toValue", p, [], ta,true );
			cfields.push(toInt);

			var enumT = {
				pos : p,
				pack : pack,
				name : makeName(name),
				meta : [{ name : ":enum", pos : p }],
				kind : TDAbstract(macro : Int),
				fields : cfields,
			};
			
			typeNames[name] = enumT;
			types.push(enumT);
		case DTypeDef(name, attrs, type):

		}
	}

	public static function buildTypes( opts : Options, hl : Bool = false ):Array<TypeDefinition> {
		var p = Context.currentPos();
		if( opts.nativeLib == null ) {
			Context.error("Missing nativeLib option for HL", p);
			return null;
		}
		// load IDL
		var file = opts.idlFile;
		var content = try {
			file = Context.resolvePath(file);
			sys.io.File.getBytes(file);
		} catch( e : Dynamic ) {
			Context.error("" + e, p);
			return null;
		}

		// parse IDL
		var parse = new webidl.Parser();
		var decls = null;
		try {
			decls = parse.parseFile(file,new haxe.io.BytesInput(content));
		} catch( msg : String ) {
			var lines = content.toString().split("\n");
			var start = lines.slice(0, parse.line-1).join("\n").length + 1;
			Context.error(msg, Context.makePosition({ min : start, max : start + lines[parse.line-1].length, file : file }));
			return null;
		}

		var module = Context.getLocalModule();
		var pack = module.split(".");
		pack.pop();
		return new Module(p, pack, hl, opts).buildModule(decls);
	}

	public static function build( opts : Options ) {
		var file = opts.idlFile;
		var module = Context.getLocalModule();
		var types = buildTypes(opts, Context.defined("hl"));
		
		if (types == null) {
			throw "Could not find types for IDL " + opts.idlFile;
			return macro : Void;
		}
		
		// Add an init function for initializing the JS module
		if (Context.defined("js")) {
			types.push(macro class Init {
				public static function init(onReady:Void->Void) {
					untyped __js__('${opts.nativeLib} = ${opts.nativeLib}().then(onReady)');
				}
			});

		// For HL no initialization is required so execute the callback immediately
		} else if (Context.defined("hl")) {
			types.push(macro class Init {
				public static function init(onReady:Void->Void) {
					onReady();
				}
			});
		}

		Context.defineModule(module, types);
		Context.registerModuleDependency(module, file);

		return macro : Void;
	}

    /**
	 * Capitalize the first letter of a string
	 * @param text The string to capitalize
	 */
	private static function capitalize(text:String) {
		return text.charAt(0).toUpperCase() + text.substring(1);
	}
}

#end
