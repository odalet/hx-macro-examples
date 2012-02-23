package ctt;
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;

using ctt.Ctt;

class Ctt 
{
	@:macro static public function build():Array<haxe.macro.Field>
	{
		var cls = Context.getLocalClass().get();
		var dataType = getDataType(cls);
		var tpl = getTemplateString(cls);
		var executeFunc = generateExecuteFunction(tpl, dataType);

		var fields = Context.getBuildFields();
		fields.push(executeFunc);
		return fields;
	}
	
	#if macro
	
	static function getTemplateString(cls:ClassType):String
	{
		if (cls.meta.has("template"))
		{
			var fileNameExpr = Lambda.filter(cls.meta.get(), function(meta) return meta.name == "template").pop().params[0];
			var fileName = getString(fileNameExpr);
			if (!neko.FileSystem.exists(fileName))
				return Context.error("Could not load template file " +fileName, fileNameExpr.pos);
			return neko.io.File.getContent(fileName);
		}
		
		return Context.error("Please specify @template metadata.", Context.currentPos());
	}
	
	static function getDataType(cls:ClassType):haxe.macro.Type
	{
		for (i in cls.interfaces)
		{
			if (i.t.get().name == "ICTemplate")
			return i.params[0];
		}
		
		return Context.error("Must implement ICTemplate.", Context.currentPos());
	}
	
	static function generateExecuteFunction(tpl:String, dataType:Type):haxe.macro.Field
	{
		var regSplit = ~/::([A-Za-z0-9_-]*)::/;
		var stringBufTP = {	name: "StringBuf", pack: [], sub: null, params: [] };
		
		var exprs = [];		
		exprs.push(EVars([ {
			name: "strBuf",
			type: TPath(stringBufTP),
			expr: ENew(stringBufTP, []).at()
		}]).at());
		
		while (regSplit.match(tpl))
		{
			exprs.push(ECall(EField(EConst(CIdent("strBuf")).at(), "add").at(), [EConst(CString(regSplit.matchedLeft())).at()]).at());
			exprs.push(Context.parse("strBuf.add(Std.string(data." +regSplit.matched(1) + "))", Context.currentPos()));
			tpl = regSplit.matchedRight();
		}
		
		exprs.push(ECall(EField(EConst(CIdent("strBuf")).at(), "add").at(), [EConst(CString(tpl)).at()]).at());
		exprs.push(EReturn(ECall(EField(EConst(CIdent("strBuf")).at(), "toString").at(), []).at()).at());

		var funcExpr = EBlock(exprs).at();

		return {
			name: "execute",
			doc: null,
			access: [APublic],
			pos: Context.currentPos(),
			meta: [],
			kind: FFun( {
				ret: TPath( {
					name: "String",
					pack: [],
					sub: null,
					params: []
				}),
				params: [],
				expr:funcExpr,
				args: [{
					name: "data",
					opt: false,
					value: null,
					type: toComplex(dataType)
				}]
			})
		};	
	}
	
	static function toComplex(type:Type):ComplexType
	{
		switch(type)
		{
			case TType(t, p):
				return TPath({
					name: t.get().name,
					pack: t.get().pack,
					sub: null,
					params: Lambda.array(Lambda.map(p, function(f) return TPType(toComplex(f))))
				});
			default:
				return Context.error("Type expected.", Context.currentPos());
		}
	}
	
	static function getString(e:Expr):String
	{
		switch(e.expr)
		{
			case EConst(c):
				switch(c)
				{
					case CString(s):
						return s;
					default:
						return Context.error("String expected.", e.pos);
				}
			default:
				return Context.error("String expected.", e.pos);
		}
	}
	
	static function at(expr:ExprDef, ?p:Position)
		return { expr: expr, pos: p == null ? Context.currentPos() : p }
	
	#end
}