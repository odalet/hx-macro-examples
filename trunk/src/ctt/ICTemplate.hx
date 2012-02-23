package ctt;

@:autoBuild(ctt.Ctt.build()) interface ICTemplate<T>
{
	public function execute(data:T):String;
}