use Regexp::Grammars;
use Data::Dumper;
use LWP::UserAgent;
use JSON;
use strict;
use warnings;

use constant BASE_URL => 'https://ws.audioscrobbler.com/2.0/?';
my $prgname = "lfm";
my $confprefix = "plugins.var.perl.$prgname";

binmode(STDOUT, ":utf8");

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
		$content = $content . "&$key=" . $params->{$key};
	}
	$rq->content($content);
	my $res = $ua->request($rq);
	return decode_json($res->content);
};

my $lfmparser = qr{
	<lfm>

	<rule: lfm>
		<[cmdchain=command]>+ % <.chainsep>

	<token: chainsep> \.\.\. | ~ | \|

	<rule: command>
		<np>
		| <user_recent_tracks>
		| <user>
		| <artist>
		| <take>
		| <extract>
		| <filter>
		| <format>
		| <dump>
		| <tell>


	#### NP Command ####
	<rule: np>
		np <[np_flags]>* <np_user=(\w+)>? ("<np_fpattern=fpattern>")? <ws>

	<rule: np_flags>
		(-a|--artist)(?{$MATCH="ARTIST";})
		| (-t|--title)(?{$MATCH="TITLE";})
		| (-A|--album)(?{$MATCH="ALBUM";})
		| (-n|--np-only)(?{$MATCH="PLAYING";})

	#### Retrieve recent tracks ####
	<rule: user_recent_tracks>
		utracks <user=name> <amount=number>

	#### User ####
	<rule: user>
		user <name>? <ws>

	#### Artist ####
	<rule: artist>
		artist <name>

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
		format "<fpattern>"

	<rule: fpattern>
		[^"]+

	#### Dump ####
	<rule: dump>
		dump

	#### Tell Command ####
	<rule: tell> <[highlight]>+

	#### Names ####
	<rule: highlight> @<name> (?{ $MATCH=$MATCH{name}; })
	<rule: name> [.:\#a-zA-Z0-9_`\[\]-]+

	#### Numbers ####
	<rule: number> [0-9]+

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

sub lfm_user_get_info {
	my $user = shift;
	my $apires = lfmjson("user.getInfo", {user => $user});
	return $apires->{user};
}

sub lfm_artistget_info {
	my $artist = shift;
	my $apires = lfmjson("artist.getInfo", {artist => $artist});
	return $apires->{artist};
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
	my $fpattern = $options->{np_fpattern} // weechat::config_string(cnf("np_fpattern"));

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
	return lfm_user_get_recent_tracks($options->{user}, $options->{amount});
}

sub uc_user {
	my $options = shift;

	my $user = $options->{name} // weechat::config_string(cnf("user"));
	my $userinfo = lfm_user_get_info($user);
	return $userinfo;
}

sub uc_artist {
	my $options = shift;
	my $artist;
	if ($options->{name} eq "-") {
		$artist = shift
	} else { $artist = $options->{name}; }

	my $artistinfo = lfm_artistget_info($artist);
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

	my @nicks = @{ $options->{highlight} };
	my $nickstring = join(", ", @nicks);
	return format_output("{nicks text:%nicks: %text}", { nicks => $nickstring,
			text => $text});
}


#### Command Processing Machinery ####
sub process_command {
	my $cmd = shift;
	my $prev = shift;

	my %callmap = (
		"np" => \&uc_np,
		"user_recent_tracks" => \&uc_user_recent_tracks,
		"user" => \&uc_user,
		"artist" => \&uc_artist,
		"take" => \&uc_take,
		"extract" => \&uc_extract,
		"filter" => \&uc_filter,
		"format" => \&uc_format,
		"dump" => \&uc_dump,
		"tell" => \&uc_tell,
	);

	for my $key (keys %{ $cmd } ) {
		if ($key && $callmap{$key}) {
			my $result = $callmap{$key}->($cmd->{$key}, $prev);
			return $result;
		}
	}
}

sub process_input {
	my $input = shift;
	my $dump = shift;

	if ($input =~ $lfmparser) {
		my $lfm = $/{lfm};
		return $lfm if $dump;

		if (my $cmdchain = $lfm->{cmdchain} ) {
			# Command Chain
			my $previous;
			foreach my $cmd (@{$cmdchain}) {
				$previous = process_command($cmd, $previous);
			}
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
	weechat::command($buffer, process_input($args));
}

sub dumpast {
	my $data = shift;
	my $buffer = shift;
	my $args = shift;
	my $dump = process_input($args, 1);
	weechat::print("", Dumper($dump));
}

if ($ARGV[0] && $ARGV[0] =~ /cli/i) {
	print process_input($ARGV[1]);
} else {
	weechat::register("lfm", "i7c", "0.3", "GPL3", "Prints last.fm shit", "", "");
	weechat::hook_command("lfm", "performs lastfm shit",
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

