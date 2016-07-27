use Regexp::Grammars;
use Data::Dumper;
use LWP::UserAgent;
use JSON;
use strict;
use warnings;

use constant BASE_URL => 'https://ws.audioscrobbler.com/2.0/?';
my $apikey = "";

binmode(STDOUT, ":utf8");

sub lfmjson {
	my $method = shift;
	my $params = shift;
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
		| <recent_tracks>
		| <take>
		| <extract>
		| <format>
		| <dump>
		| <tell>


	#### NP Command ####
	<rule: np>
		np <[np_flags]>* <np_user=(\w+)>? ("<np_fpattern=fpattern>")?

	<rule: np_flags>
		(-n|--np-only)(?{$MATCH="PLAYING";})

	#### Retrieve recent tracks ####
	<rule: recent_tracks>
		tracks <user=name> <amount=number>

	#### Take Array element ####
	<rule: take>
		take <index=number>

	#### Extract track info from track lement####
	<rule: extract>
		extract

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
	<rule: name> [a-zA-Z0-9_`\[\]]+

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

sub array_take {
	my $array = shift;
	my $which = shift;
	return @{$array}[$which];
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

#### User Commands ####
sub uc_np {
	my $options = shift;
	my %flags = map { $_ => 1 }  @{ $options->{np_flags} };

	my $result =
		extract_track_info(array_take(
				lfm_user_get_recent_tracks($options->{np_user}, 1), 0));

	return format_output($options->{np_fpattern}, $result);
}

sub uc_recent_tracks {
	my $options = shift;
	return lfm_user_get_recent_tracks($options->{user}, $options->{amount});
}

sub uc_take {
	my $options = shift;
	my $array = shift;
	return array_take($array, $options->{index});
}

sub uc_extract {
	my $options = shift;
	my $trackinfo = shift;
	return extract_track_info($trackinfo);
}

sub uc_format {
	my $options = shift;
	my $data = shift;

	return format_output($options->{fpattern}, $data);
}

sub uc_dump {
	my $options = shift;
	my $data = shift;
	return Dumper($data);
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
		"recent_tracks" => \&uc_recent_tracks,
		"take" => \&uc_take,
		"extract" => \&uc_extract,
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

	if ($input =~ $lfmparser) {
		my $lfm = $/{lfm};
		#print Dumper($lfm);

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
		# Handle error
	}
}

sub lfm {
	weechat::print("", "hihihi");
}

weechat::register("lfm", "i7c", "0.3", "GPLv3", "Prints last.fm shit", "", "");
weechat::hook_comand("lfm", "/lfm performs lastfm shit", "", "", "lfm", "");
