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

"lfm.pl is a weechat plugin that allows to query the last.fm-API in
several ways and 'say' the results to current buffers.

lfm.pl adds one command to weechat called /$prgname. /$prgname itself
accepts a 'command chain' (which can has the length of one, i.e. a
single command, of course). In a chain the commands are separated either
by a pipe (|) or by a semicolon (;). The commands are executed from left
to right and the result of any command is passed to the next command.
The result of the last command is posted to the chat. Sometimes it might
be desirable to prevent a command from passing its result to the next
command in the command chain. In that case you can use a ^ at the end of
the command to redirect the output to nowhere. I suggest to use the ;
command separator after a ^ redirect, although the pipe | works all the
same.

While previous versions of this script only provided access to
high-level commands, this version exposes all the internal commands to
the user as well and allows to define own commands. Usually, the user
has all means to 'rewrite' the high-level commands and of course create
new useful high-level commands with these means. In the following we
describe all available commands.


np [-u|--user <user>] [-p|--pattern <format pattern>] [<flags>]
***************************************************************

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
****

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

	#### Aliases ####
	<rule: alias>
		!? <name>
};

sub format_output {
	my $pattern = shift;
	my $params = shift;
	my $scheme;
	my $varlist;
	my $rest;
	my $result;

	while ($pattern) {
		# get next { } group
		($varlist, $scheme, $rest) = $pattern =~ m/\{([\w\s]+):([^\{\}]*)\}(.*)/g;
		$pattern = $rest;

		if ($varlist && $scheme) {
			my @vars = split(/\s+/, $varlist);
			my $valid = 1;
			foreach my $x (@vars) {
				if ($params->{$x}) {
					$scheme =~ s/%$x/$params->{$x}/g;
				} else { $valid = 0; }
			}
			$result .= $scheme if $valid;
		}
	}
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
	my $user = $options->{np_user} // weechat::config_string(cnf("user"));
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
	my $user = $options->{user} // weechat::config_string(cnf("user"));
	my $number = $options->{number} // 10;
	return lfm_user_get_recent_tracks($user, $number);
}

sub uc_user_artist_tracks {
	my $options = shift;
	my $previous = shift;

	my $user = $options->{user} // weechat::config_string(cnf("user"));
	my $artist = $options->{artist} // $previous;
	return lfm_user_get_artist_tracks($user, $artist);
}

sub uc_user {
	my $options = shift;

	my $user = $options->{name} // weechat::config_string(cnf("user"));
	my $userinfo = lfm_user_get_info($user);
	return $userinfo;
}

sub uc_artist {
	my $options = shift;
	my $previous = shift;

	my $params = {};
	$params->{artist} = $options->{artist} // $previous;
	$params->{user} = $options->{user} // weechat::config_string(cnf("user"));
	$params->{lang} = $options->{lang};
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
	return format_output("{nicks text:%nicks: %text}", { nicks => $nickstring,
			text => $text});
}

sub uc_track {
	my $options = shift;
	my $previous = shift;

	my $params = {};
	$params->{artist} = $options->{artist} // $previous->{artist};
	$params->{track} = $options->{track} // $previous->{track};
	$params->{username} = $options->{user} // $previous->{user} // weechat::config_string(cnf("user"));
	$params->{mbid} = $options->{id};
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

sub uc_alias {
	my $options = shift;
	my $previous = shift;

	my $input = weechat::config_string(cnf("alias." . $options->{name}));
	if (! $input) {
		weechat::print("", "ERROR: No such alias: " . $options->{name});
		return "";
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

