import ae.sys.log;
import ae.utils.sini;

struct Config
{
	string addr;
	ushort port = 80;

	string token;
}

immutable Config config;

shared static this()
{
	config = loadIni!Config("ghdaemon.ini");
}

// ***************************************************************************

Logger log;

static this()
{
	log = createLogger("GHDaemon");
}

// ***************************************************************************

immutable components = ["DMD", "Druntime", "Phobos", "Tools"];
