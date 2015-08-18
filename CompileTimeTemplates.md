# Problem description #

We start by looking at the usage of a compile time template:

```
class Main 
{
	static function main() 
	{
		var uview = new UserTemplate();
		var result = uview.execute( { name:"Dr. Wily", age: 12 } );
	}
}
```

The variable _result_ should then be a String, based on the template String specified by UserTemplate, in which, by convention, each occurrence of "::name::" is replaced by "Dr. Wily" and each occurence of "age" is replaced by the integer value 12.

For instance, a user template could be this HTML template:

```
<div class='user'>
	<span>Name: ::name::</span>
	<span>Age: ::age::</span>
</div>
```

# General approach #

Working with this kind of template requires two steps:
  * retrieve the template as String and
  * replace ::template\_variables:: with values.

The first step can generally be performed at compile time because it is known which templates are used. Haxe allows this by using resources, as described in the official documentation: http://haxe.org/doc/cross/template Here, we will approach this differently by specifying template files as Metadata and loading the files in macros.

The second step has to be done at runtime because in the general case, the values are known only at runtime. However, we will prepare as much as possible during compile time to lower the resource and performance cost during runtime.

# Basic setup #

## The abstract interface and concrete template class ##
We start by introducing the general interface describing a template. This is simple because all we really care about is the template having an execute function:

```
interface ICTemplate<T>
{
	public function execute(data:T):String;
}
```

We go the type-safe route by using T as a type parameter. We assume that T is something that has fields corresponding to the used template parameters, i.e. "name" and "age" for our ongoing example. There is no need to verify this assumption by hand, the compiler will notice any problems by itself. For our example, the concrete data type looks like this:

```
typedef User =
{
	name:String,
	age: Int
}
```

This allows us to specify the UserTemplate class as such:

```
class UserTemplate implements ICTemplate<User>
{
	public function new() 
	{	
	}
}
```

## Our macro's job description ##
So far, there hasn't been any notion of macros whatsoever. Trying to compile the code at this point will however fail due to UserTemplate not implementing the execute method as dictated by ICTemplate. We don't want to do this by hand for each Template class, but we also can't implement anything in ICTemplate because that's an interface.

So why, you might ask, are we not implementing _execute_ in a base class of UserTemplate? There are two reasons for that:
  * it would have to do all the work during runtime and
  * this tutorial is about macros and compile time templates.

This leads to the job description of our macro:
  1. Load a template from a specified file.
  1. Provide the _execute_ method which can be called during runtime.

Let's tackle these steps separately.

# Loading the template from a file #

## What to load? ##
In order to load something, we have to know what we actually want to load. While it'd be perfectly fine to derive this from the template class name by some convention (i.e. UserTemplate -> load templates/user.tpl), there is a cleaner and more flexible way by specifying class Metadata:

```
@template("templates/user.tpl")
class UserTemplate ...
```

Using @template here is our choice, we can name it differently if we so desire.

## Where to load? ##
Now, where do we put the code to actually load stuff? There's a nice haxe feature that helps us here and finally introduces us to macros, which is type building. Reading the official documentation (http://haxe.org/manual/macros/build) explains the general usage of @:build and @:autoBuild. To put it simple, @:build lets you specify a (macro) function that returns the fields for the type @:build is used on. @:autoBuild is similar, but also works on classes extending or implementing the class or interface which is annotated with @:autoBuild.

This is exactly what we need here. If we use @:autoBuild on our ICTemplate interface, we can put some code for all classes implementing it, which includes our example UserTemplate. So let's do that:

```
@:autoBuild(Ctt.build()) interface ICTemplate<T>
{
	public function execute(data:T):String;
}
```

At this stage, ICTemplate is already finished and there is no need for further modifications for what we want to do. The parameter of @:autoBuild is actually a (macro) function call. The corresponding function does not yet exist, so here's the remedy:

```
class Ctt 
{
	@:macro static public function build():Array<haxe.macro.Field>
	{
		var fields = Context.getBuildFields();
		return fields;
	}
}
```

I sneaked two lines of code in there so it actually compiles. Before elaborating on that, take your time and look at the return type of _build_. It's an array of haxe.macro.Field objects, which makes sense in the context of type building. Go ahead and look at the definition of haxe.macro.Field: http://haxe.org/api/haxe/macro/field Does it make sense to you? You are allowed to be confused by "pos" and you might wonder what's going on when following the definitions related to "kind", but the others should be obvious.

Either way, we now have an entry point. Consider _build_ just like _main_, i.e. the entry to a separate program. This program is run in a neko environment with a specific context.

## Context? ##

I find it difficult to generally describe what a context is, especially because haxe.macro.Context provides, among truly contextual method, some general utility methods. When using @:build or @:autoBuild, the context is basically the type that is currently built. For our concrete example, consider the context to be our UserTemplate class.

With that mindset, explaining the first line of above _build_ method is possible. _Context.getBuildFields_ returns all fields of the type that is in our current context, i.e. the fields of UserTemplate in our example. If we were to put _trace(fields)_ there, it would print the definition of our UserTemplate's constructor "new", which is the only field it currently has.

There's actually not much left to do, we just want to push the field definition of our "execute" method onto the _fields_ array. We got a little off track though and still need to load our template string.

## How to load? ##

```
class Ctt 
{
	@:macro static public function build():Array<haxe.macro.Field>
	{
		var fields = Context.getBuildFields();
		var cls = Context.getLocalClass().get();
		var tpl = getTemplateString(cls);
		return fields;
	}
}
```

_Context.getLocalClass_ does exactly what you think it does, which is returning the class definition for our UserTemplate class. Again, look at what ClassType is: http://haxe.org/api/haxe/macro/classtype You don't have to understand everything as of yet, it's suffice to know you can get all information about a given class here. Any idea what we do with that here? You should be able to tell if you paid attention!

For the remaining template loading task, you can almost forget that we're coding a macro and treat this like a normal neko application. Here's the definition of _getTemplateString_:

```
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
```

That's right, of course we need our class definition to access that @template metadata we defined earlier. The Lambda line might look a little intimidating, but it really only accesses the metadata value we want. So what's the type of _fileNameExpr_? Checking http://haxe.org/manual/metadata, a metadata value can be quite a lot of things, and we're obviously not working with _Dynamic_, so...?

## Enter expressions ##

Yes, it's an expression, written _Expr_ in haxe. Checking its definition, you will see that it is composed of a _Position_ and an _ExprDef_. The former is the position of the expression, given by the containing file and the offset within that file. It is mainly used to report accurate errors to the user.

_ExprDef_ is the heart of everything, an enumeration that exhaustively describes haxe syntax. Take a good, long look at it: http://haxe.org/api/haxe/macro/exprdef Understanding this is essential for most macros. Read through it and think about how each construct translates back to source code.

Study it until you can write the _getString_ method that is used above. It takes an _Expr_ as argument and returns a String if the expression actually is a String. In all other cases, you can make it return a _Context.error_. I will not give away the solution here, but the function will probably start with a _switch(e.expr)_ if _e_ is the name of the argument.

## Wrapping up ##

After we obtained the _fileName_ string, we only need to load the file through normal neko functions. Remember, we are inside the neko environment and can use most neko functions here. Isn't that cool? This also concludes the first part of our macro's task. We now have a String version of our template in the _tpl_ variable inside our _build_ function and can work from there. The next task is to create the _execute_ field with the proper logic behind it.