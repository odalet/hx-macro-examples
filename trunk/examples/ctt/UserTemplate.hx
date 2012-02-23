package ;
import ctt.ICTemplate;

typedef User =
{
	name:String,
	age: Int
}

@template("templates/user.tpl")
class UserTemplate implements ICTemplate<User>
{
	public function new() 
	{
		
	}
}