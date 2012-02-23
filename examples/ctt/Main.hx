package ;

/**
 * ...
 * @author Simon Krajewski
 */

class Main 
{
	
	static function main() 
	{
		var uview = new UserTemplate();
		var result = uview.execute( { name:"Dr. Wily", age: 12 } );
		trace(result);
	}
	
}