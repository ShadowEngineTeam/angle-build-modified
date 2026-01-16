package;

class Config
{
	public var os:String = '';

	public var cpu:String = '';

	public var environment:String = '';

	public var args:Array<String> = [];

	public function new():Void {}

	public function getExportPath():String
	{
		return environment.length > 0 ? 'out/$os-$cpu-$environment' : 'out/$os-$cpu';
	}

	public function getAngleArgs():String
	{
		if (environment.length > 0)
			return ['target_os="$os"', 'target_cpu="$cpu"', 'target_environment="$environment"'].concat(args).join(' ');
		else
			return ['target_os="$os"', 'target_cpu="$cpu"'].concat(args).join(' ');
	}
}
