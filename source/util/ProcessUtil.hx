package util;

/**
 * Utility class for process and command-line operations.
 */
class ProcessUtil
{
	/**
	 * Checks whether a command exists on the system.
	 * This method will return true if the command is found, and false otherwise.
	 * 
	 * @param cmd The command to check for existence.
	 * @return `true` if the command exists, `false` otherwise.
	 */
	public static function commandExists(cmd:String):Bool
	{
		var result:Int = 0;

		if (Sys.systemName() == "Windows")
			// For Windows, use 'where' command to check if the command exists
			result = Sys.command("cmd", ["/c", "where", cmd, ">", "NUL", "2>&1"]);
		else
			// For Unix-like systems, use 'command -v' to check if the command exists
			result = Sys.command("/bin/sh", ["-c", "command -v " + cmd + " > /dev/null 2>&1"]);

		return result == 0;
	}
}
