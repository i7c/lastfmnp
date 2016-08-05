use Regexp::Grammars;
use Data::Dumper;
use LWP::UserAgent;
use JSON;
use strict;
use warnings;

use constant BASE_URL => 'https://ws.audioscrobbler.com/2.0/?';
my $prgname = "lfm";
my $confprefix = "plugins.var.perl.$prgname";

my $LFMHELP =

"$prgname.pl is a weechat plugin that allows to query the last.fm-API in
several ways and 'say' the results to current buffers.

lfm.pl adds one command to weechat called /$prgname. /$prgname itself
accepts a 'command chain' (which can have the length of one, i.e. a
single command, of course). In a chain the commands are separated either
by a pipe (|) or by a semicolon (;). The commands are executed from left
to right and the result of any command is passed to the next command.
The result of the last command is posted to the chat. Sometimes it might
be desirable to prevent a command from passing its result to the next
command in the command chain. In that case you can use a ^ at the end of
the command to redirect the output to nowhere. I suggest to use the ;
command separator after a ^ redirect, although the pipe | works all the
same. Results are also passed to the following command if you use just a
;. So the separators | and ; are entirely equivalent.

While previous versions of this script only provided access to
high-level commands, this version exposes all the internal commands to
the user as well and allows to define own commands. Usually, the user
has all means to 'rewrite' the high-level commands and of course create
new useful high-level commands with these means. In the following we
describe all available commands and language features.

There are some essential configuration options which the user must set.

/set plugins.var.perl.$prgname.apikey

must be set to a valid last.fm API-key. You can get one on
http://www.last.fm/api

/set plugins.var.perl.$prgname.user

should be set to *your* last.fm username. Many commands have a --user
flag which - if omitted -  will use this username as default value.

/set plugins.var.perl.$prgname.pattern.np \"{artist title:I'm playing %artist - %title}{album: (%album)}\"

This pattern is essential as it is used by the /$prgname np command.

With these three settings, /$prgname np should already work.

To use the tell function you have to set this pattern:

/set plugins.var.perl.$prgname.pattern.tell \"{nicks text:%text ← %nicks}\"


SUBSHELLS AND VARIABLES
***********************

$prgname knows 'subshells'. A subshell is just another valid command in
a command chain. It looks like this:

\$ [invar] { <cmdchain> } [outvar]

The cmdchain is any non-empty command chain (which could contain
subshells again). The invar and outvar parts are optional. They are a
primivitve but effective implementation of variables. The content of
invar is passed to the first command in the command chain as input. The
outvar stores the result of the last command in the command chain. Note that
the output is still passed to a subsequent command, even if you store it.

Examples:

\${np -a} art

This stores the most recently played artist in a variable called art.


\${np -a} art | \${artist} artjson

This first stores the most recently played artist in the variable art,
then looks up this artist (the first subshell still passes the result to
the next command) and the returning json is stored in a variable called
artjson.

There is one *special* variable called env which represents the whole
environemnt, i.e. all variables. It can be used both as invar and outvar
with slightly different meaning. Note that env is just another HASH and
any command that can take a HASH as input can take env as input. So you
may do something like:

\$ env { format '{art:Artist: %art.}' }

Here format takes the environment as input and you can read any
variables from it, in that case the previously set art variable. env can
also be used as outvar, but *only* if the result of the last command is
a HASH. In this case all the keys in this hash are used as new variables
in the environment and set to the respective values. Example:

Say, command C returns a hash {x => 1, y => 42}. If you run

\$ { C } env

the variable x will be 1 and y will be 42 afterwards.

Hint: a very useful way to show the entire environment is to pass it to
dump which will print it on buffer 1. Just do

\$ env { dump }

There is only one environment which is shared among all subshells and the
top-level shell! If you nest subshells and set variables they will still
appear (and potentially overwrite) any variable with the same name. E.g.:

\${ \${np -a} artist^; np -t} title^; \$ env {dump}

will show you two variables artist and title and thus this command is
equivalent to

\${np -a} artist^; \${np -t} title^; \$ env {dump}

The environment is reset to an empty environment whenever you run
/$prgname. Effectively that means that the variables live for one
execution of /$prgname.


ENVIRONMENT
***********

The section above describes how you can set variables and how they can
be used to feed commands. The only way so far is to use the invar of a
subshell which effectively changes what is passed as input to a command.
There is another way how variables can change the behaviour of commands.
If a command is 'environment-aware' it may read variables with
particular names and use their value. This can lead to cases in which a
command has several possible information sources available. In the
extreme case, a command can have an explicit argument, a value passed
via the input (from a previous command), an environment variable that is
set and a configuration value which often acts as default. All commands
need to define a precedence of these options and it *usually* is

1. explicit parameter
2. value via input from previous command
3. environment variable
4. configuration option

There are exceptions, especially such where some of the possibilities
are not available. Which env variables a command recognises is usually
described in the help section of this command.


ALIASES
*******

You can create aliases by setting configuration variables. For example,
if you set /set plugins.var.perl.lfm.alias.comp_artist to a valid
command chain as value, you effectifely created the alias comp_artist.

You can execute the alias exactly as any other command by running:

/lfm !comp_artist

The ! *may* be ommitted if it is still unambigious that you are
referring to an alias. If in doubt, just add the ! in front. Aliases
can be used in command chains just like normal commands:

/lfm !comp_artist | dump

Aliases can take positional arguments. Say you create the following alias

/set plugins.var.perl.lfm.alias.xtracks \"utracks -u \$1 -n \$2\"

you can use the alias with arguments: /lfm !xtracks iSevenC 3

Arguments can be single words (or numbers for that matter) or
single-quoted strings. Please note that alias arguments are simple
string replacements that happen *before* the alias is executed. Alias
arguments can only be literal and not the evaluation of some complex
term. If you pass a single word the respective \$x will be replaced by
that word. If you pass 'a single quoted string' the \$x will be replaced
by that string *including* the ''. In most cases this is what you want.
Because aliases work with simple string-based expansion, you can even
do things like

/set plugins.var.perl.lfm.alias.test \"utracks | \$1\"

/lfm !test dump

If you want to replace \$x by a string (more than one word) but
without any '' you can use [ ]. Examples:

/set plugins.var.perl.lfm.alias.test \"utracks \$1\"

/lfm !test [| dump]


COMMANDS
********

np [-u|--user <user>] [-p|--pattern <format pattern>] [<flags>]

	Prints the currently played or (if not available) the most
	recently played song.

	You can specify a last.fm user. If you don’t the user set in
	$confprefix.user will be queried.

	You can specify a format pattern. If you don’t the pattern set
	in $confprefix.np_fpattern will be used.

	Flags:
	-n:\t\tOnly return result if song is currently playing
	-t:\t\tOnly return the title of the song (overrides format pattern)
	-a:\t\tOnly return the artist of the song (overrides format pattern)
	-A:\t\tOnly return the album of the song (overrides format pattern)

	You can specify only one of -t -a or -A (or undefined shit happens).


dump

	Takes anything as input and dumps it to the weechat buffer. This is very
	useful to debug own commands (or chains) and see their result. dump
	provides no output.

	Example:
	/$prgname user | dump
";

binmode(STDOUT, ":utf8");

my %env = ();

sub cnf {
	my $option = shift;
	return weechat::config_get("$confprefix.$option");
}

sub lfmjson {
	my $method = shift;
	my $params = shift;
	my $apikey = weechat::config_string(cnf("apikey"));
	my $url = BASE_URL . "format=json&api_key=$apikey&method=$method";
	my $ua = LWP::UserAgent->new;
	$ua->agent("lastfmnp/0.0");

	my $rq = HTTP::Request->new(GET => 'https://ws.audioscrobbler.com/2.0/');
	my $content = "format=json&api_key=$apikey&method=$method";
	foreach my $key (keys %$params) {
		if ($params->{$key}) {
			$content = $content . "&$key=" . $params->{$key};
		}
	}
	$rq->content($content);
	my $res = $ua->request($rq);
	return decode_json($res->content);
};

my $lfmparser = qr{
	<lfm>

	<rule: lfm>
		<[cmdchain=command]>+ % <.chainsep>

	<token: chainsep> ; | ~ | \|

	<rule: command>
		(<np>
		| <utracks>
		| <uatracks>
		| <user>
		| <artist>
		| <take>
		| <extract>
		| <filter>
		| <format>
		| <dump>
		| <tell>
		| <track>
		| <subshell>
		| <variable>
		| <alias>) <tonowhere=(\^)>?


	#### NP Command ####
	<rule: np>
		np
		(
			(-u|--user) <np_user=(\w+)>
			| (-p|--pattern) '<np_fpattern=fpattern>'
		)*
		<[np_flags]>* <ws>

	<rule: np_flags>
		(-a|--artist)(?{$MATCH="ARTIST";})
		| (-t|--title)(?{$MATCH="TITLE";})
		| (-A|--album)(?{$MATCH="ALBUM";})
		| (-n|--np-only)(?{$MATCH="PLAYING";})

	#### Retrieve recent tracks ####
	<rule: utracks>
		utracks
		(
			((-u|--user) <user=name>)
			| ((-n|--number) <number>)
		)* <ws>

	<rule: uatracks>
		uatracks
		(
			((-u|--user) <user=name>)
			| ((-a|--artist) <artist=name>)
		)* <ws>

	#### User ####
	<rule: user>
		user <name>? <ws>

	#### Artist ####
	<rule: artist>
		artist
		(
			(-a|--artist) (<artist=name> | '<artist=str>')
			| (-u|--user) <user=name>
			| (-l|--lang) <lang=name>
			| (-i|--id) <id=name>
		)* <ws>

	#### Take Array element ####
	<rule: take>
		take <index=number>

	#### Extract track info from track lement####
	<rule: extract>
		extract track
		| extract user

	#### Filter ####
	<rule: filter>
		filter (<[filter_pattern]>+ % ,)

	<rule: filter_pattern>
		<from=name> -\> <to=name>

	#### Format command ####
	<rule: format>
		format '<fpattern>'

	<rule: fpattern>
		[^']+

	#### Dump ####
	<rule: dump>
		dump

	#### Tell Command ####
	<rule: tell> @ (<.ws><[name]>)+

	#### Names ####
	<rule: name> [.:\#?a-zA-Z0-9_`\[\]-]+

	<rule: str> [^']+

	#### Numbers ####
	<rule: number> [0-9]+

	#### Track Info ####
	<rule: track>
		track
		(
			(-u|--user) <user=name>
			| (-a|--artist) (<artist=name> | '<artist=str>')
			| (-t|--track) (<track=name> | '<track=str>')
		)* <ws>

	<rule: subshell>
		\$ <in=name>? { <sublfm=lfm> } <out=name>?

	<rule: variable>
		\$ \( ('<value=str>' | <value=name>) \) <out=name>?

	#### Aliases ####
	<rule: alias>
		!? <name> <[args=aliasarg]>*

	<rule: aliasarg>
		(<arg=(\w+)> | <arg=('[^']*')> | \[<arg=([^\]]*)>\])
};

sub format_output {
	my $pattern = shift;
	my $params = shift;
	my $scheme;
	my $varlist;
	my $rest;
	my $result;

	if ($env{_fpattern}) { $pattern = $env{_fpattern}; }
	while ($pattern) {
		# get next { } group
		($varlist, $scheme, $rest) = $pattern =~ m/\{([\w\s]*):([^\{\}]*)\}(.*)/g;
		$pattern = $rest;

		if ($scheme) {
			my @vars = ();
			if ($varlist) {
				@vars = split(/\s+/, $varlist);
			}
			my $valid = 1;
			foreach my $x (@vars) {
				if ($params->{$x}) {
					utf8::encode($params->{$x});
					$scheme =~ s/%$x/$params->{$x}/g;
				} else { $valid = 0; }
			}
			$result .= $scheme if $valid;
		}
	}
	utf8::decode($result);
	return $result;
}

sub lfm_user_get_recent_tracks {
	my $user = shift;
	my $limit = shift;

	my $apires = lfmjson("user.getRecentTracks",
		{user => $user, limit => $limit });
	return $apires->{recenttracks}->{track};
}

sub lfm_user_get_artist_tracks {
	my $user = shift;
	my $artist = shift;

	my $apires = lfmjson("user.getArtistTracks", {user => $user, artist => $artist});
	return $apires;
}

sub lfm_user_get_info {
	my $user = shift;
	my $apires = lfmjson("user.getInfo", {user => $user});
	return $apires->{user};
}

sub lfm_artistget_info {
	my $params = shift;
	my $apires = lfmjson("artist.getInfo", $params);
	return $apires->{artist};
}

sub lfm_track_get_info {
	my $params = shift;
	my $apires = lfmjson("track.getInfo", $params);
	return $apires;
}

sub array_take {
	my $array = shift;
	my $which = shift;
	return @{$array}[$which];
}

sub filter {
	my $data = shift;
	my $patterns = shift;
	my $result = {};

	foreach my $pattern (@{$patterns}) {
		my @steps = split(/\./, $pattern->{from});
		my $current = $data;
		foreach my $step (@steps) {
			if ($step =~ /\d+/) {
				$current = $current->[$step];
			} else {
				$current = $current->{$step};
			}
		}
		$result->{$pattern->{to}} = $current;
	}
	return $result;
}

sub extract_track_info {
	my $trackinfo = shift;

	my $data = {};
	if (my $track = $trackinfo) {
		$data->{title} = $track->{name};
		$data->{id} = $track->{mbid};
		$data->{artist} = $track->{artist}->{"#text"};
		$data->{artistId} = $track->{artist}->{mbid};
		$data->{url} = $track->{url};
		$data->{album} = $track->{album}->{"#text"};
		$data->{albumId} = $track->{album}->{mbid};
		$data->{active} = 1 if ($track->{'@attr'}->{nowplaying})
	}
	return $data;
}

sub extract_user_info {
	my $userinfo = shift;

	my $data = {};
	if (my $user = $userinfo) {
		$data->{gender} = $userinfo->{gender};
		$data->{age} = $userinfo->{age};
		$data->{url} = $userinfo->{url};
		$data->{playcount} = $userinfo->{playcount};
		$data->{country} = $userinfo->{country};
		$data->{name} = $userinfo->{name};
		$data->{playlists} = $userinfo->{playlists};
		$data->{registered} = $userinfo->{registered}->{unixtime};
	}
	return $data;
}

#### User Commands ####
sub uc_np {
	my $options = shift;
	my %flags = map { $_ => 1 }  @{ $options->{np_flags} };
	my $user = $options->{np_user}
		// $env{_user}
		// weechat::config_string(cnf("user"));
	my $fpattern = $options->{np_fpattern} // weechat::config_string(cnf("pattern.np"));

	my $result =
		extract_track_info(array_take(
				lfm_user_get_recent_tracks($user, 1), 0));

	if ($flags{"PLAYING"} && ! $result->{active}) { return ""; }

	$fpattern = "{album:%album}" if ($flags{"ALBUM"});
	$fpattern = "{title:%title}" if ($flags{"TITLE"});
	$fpattern = "{artist:%artist}" if ($flags{"ARTIST"});

	return format_output($fpattern, $result);
}

sub uc_user_recent_tracks {
	my $options = shift;
	my $user = $options->{user} // $env{_user}
		// weechat::config_string(cnf("user"));
	my $number = $options->{number} // $env{_num} // 10;
	return lfm_user_get_recent_tracks($user, $number);
}

sub uc_user_artist_tracks {
	my $options = shift;
	my $previous = shift;

	my $user = $options->{user} // $env{_user}
		// weechat::config_string(cnf("user"));
	my $artist = $options->{artist} // $previous // $env{_artist};
	return lfm_user_get_artist_tracks($user, $artist);
}

sub uc_user {
	my $options = shift;

	my $user = $options->{name} // $env{_user}
		// weechat::config_string(cnf("user"));
	my $userinfo = lfm_user_get_info($user);
	return $userinfo;
}

sub uc_artist {
	my $options = shift;
	my $previous = shift;

	my $params = {};
	$params->{artist} = $options->{artist} // $previous // $env{_artist};
	$params->{user} = $options->{user} // $env{_user}
		// weechat::config_string(cnf("user"));
	$params->{lang} = $options->{lang} // $env{_lang};
	$params->{id} = $options->{id};

	my $artistinfo = lfm_artistget_info($params);
	return $artistinfo;
}

sub uc_take {
	my $options = shift;
	my $array = shift;
	return array_take($array, $options->{index});
}

sub uc_extract {
	my $options = shift;
	my $info = shift;

	if ($options =~ /extract track/) {
		return extract_track_info($info);
	} elsif ($options =~ /extract user/) {
		return extract_user_info($info);
	}
}

sub uc_filter {
	my $options = shift;
	my $data = shift;

	my $pattern = $options->{filter_pattern};
	return filter($data, $pattern);
}

sub uc_format {
	my $options = shift;
	my $data = shift;

	return format_output($options->{fpattern}, $data);
}

sub uc_dump {
	my $options = shift;
	my $data = shift;
	weechat::print("", Dumper($data));
	return "";
}

sub uc_tell {
	my $options = shift;
	my $text = shift;

	my @nicks = @{ $options->{name} };
	my $nickstring = join(", ", @nicks);
	my $fpattern = $env{_tellpattern} // weechat::config_string(cnf("pattern.tell"));
	return format_output($fpattern, { nicks => $nickstring, text => $text});
}

sub uc_track {
	my $options = shift;
	my $previous = shift;

	my $params = {};
	$params->{artist} = $options->{artist} // $previous->{artist} // $env{_artist};
	$params->{track} = $options->{track} // $previous->{track} // $env{_track};
	$params->{username} = $options->{user} // $previous->{user} // $env{_user}
		// weechat::config_string(cnf("user"));
	$params->{mbid} = $options->{id} // $previous->{id} // $env{_id};
	return lfm_track_get_info($params);
}

sub uc_subshell {
	my $options = shift;
	my $previous = shift;

	# explicit input overrides
	if ($options->{in}) {
		$previous = $env{$options->{in}};
	}
	my $out = process_cmdchain($options->{sublfm}->{cmdchain}, $previous);

	if ($options->{out}) {
		if ($options->{out} eq "env") {
			if (ref($out) eq "HASH") {
				foreach my $k (keys %{$out}) {
					$env{$k} = $out->{$k};
				}
			} else {
				weechat::print("", "lfm: tried to embed something other than hash in environment");
			}
		} else {
			$env{$options->{out}} = $out;
		}
	}
	return $out;
}

sub uc_variable {
	my $options = shift;
	my $previous = shift;

	my $value = $options->{value};
	if ($options->{out}) {
		$env{$options->{out}} = $value;
	}
	return $value;
}

sub uc_alias {
	my $options = shift;
	my $previous = shift;

	my $input = weechat::config_string(cnf("alias." . $options->{name}));
	if (! $input) {
		weechat::print("", "ERROR: No such alias: " . $options->{name});
		return "";
	}
	if ($options->{args}) {
		for (my $i = scalar @{$options->{args}}; $i > 0; $i--) {
			my $arg = $options->{args}->[$i - 1]->{arg};
			$input =~ s/\$$i/$arg/g;
		}
	}
	return process_input($input, $previous);
}


#### Command Processing Machinery ####
sub process_command {
	my $cmd = shift;
	my $prev = shift;

	my %callmap = (
		"np" => \&uc_np,
		"utracks" => \&uc_user_recent_tracks,
		"uatracks" => \&uc_user_artist_tracks,
		"user" => \&uc_user,
		"artist" => \&uc_artist,
		"take" => \&uc_take,
		"extract" => \&uc_extract,
		"filter" => \&uc_filter,
		"format" => \&uc_format,
		"dump" => \&uc_dump,
		"tell" => \&uc_tell,
		"track" => \&uc_track,
		"subshell" => \&uc_subshell,
		"variable" => \&uc_variable,
		"alias" => \&uc_alias,
	);

	for my $key (keys %{ $cmd } ) {
		if ($key && $callmap{$key}) {
			my $result = $callmap{$key}->($cmd->{$key}, $prev);
			return $result;
		}
	}
}

sub process_cmdchain {
	my $cmdchain = shift;
	my $previous = shift;

	foreach my $cmd (@{$cmdchain}) {
		$previous = process_command($cmd, $previous);
		if ($cmd->{tonowhere}) { undef $previous; }
	}
	return $previous;
}

sub process_input {
	my $input = shift;
	my $previous = shift;

	if ($input =~ $lfmparser) {
		my $lfm = $/{lfm};

		if (my $cmdchain = $lfm->{cmdchain} ) {
			$previous = process_cmdchain($lfm->{cmdchain}, $previous);
			return $previous;
		} else {
			#TODO: error case
		}
	} else {
		weechat::print("", "lfm: Input error");
	}
}

sub lfm {
	my $data = shift;
	my $buffer = shift;
	my $args = shift;

	%env = ();
	$env{env} = \%env;
	weechat::command($buffer, process_input($args));
}

sub dumpast {
	my $data = shift;
	my $buffer = shift;
	my $args = shift;

	if ($args =~ $lfmparser) {
		my $lfm = $/{lfm};
		weechat::print("", Dumper($lfm));
		if (my $cmdchain = $lfm->{cmdchain} ) {
			# Command Chain
			foreach my $cmd (@{$cmdchain}) {
				if ($cmd->{"alias"}) {
					weechat::print("", "Dumping AST for alias " . $cmd->{alias}->{name});
					my $input = weechat::config_string(cnf("alias." . $cmd->{alias}->{name}));
					dumpast($data, $buffer, $input);
				}
			}
		}
	} else {
		weechat::print("", "ERROR: No valid input. No AST available.");
	}
}

if ($ARGV[0] && $ARGV[0] =~ /cli/i) {
	print process_input($ARGV[1]);
} else {
	weechat::register("lfm", "i7c", "0.3", "GPL3", "Prints last.fm shit", "", "");
	weechat::hook_command("lfm", $LFMHELP,
		"lfm",
		"",
		"",
		"lfm", "");
	weechat::hook_command("dumpast", "dumps lastfm shit",
		"dumpast",
		"",
		"",
		"dumpast", "");
}

