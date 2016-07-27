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
		<[cmdlist=command]>+ % <.listsep>
		| : <[cmdchain=command]>+ % <.chainsep>

	<token: listsep> ;
	<token: chainsep> \.\.\.

	<rule: command>
		<np>
		| <tell>


	#### Tell Command ####
	<rule: tell> <[highlight]>+

	#### NP Command ####
	<rule: np>
		np <[np_flags]>* <np_user=(\w+)>? ("<np_fpattern>")?

	<rule: np_flags>
		(-n|--np-only)(?{$MATCH="PLAYING";})

	<rule: np_fpattern>
		[^"]+

	#### Names ####
	<rule: highlight> @<name> (?{ $MATCH=$MATCH{name}; })
	<rule: name> [a-zA-Z0-9_`\[\]]+

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

sub lfm_np {
	my $user = shift;
	my $limit = shift;

	my $apires = lfmjson("user.getRecentTracks",
		{user => $user, limit => $limit });

	my $data = {};
	if (my $track = $apires->{recenttracks}->{track}[0]) {
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

sub uc_np {
	my $options = shift;
	my %flags = map { $_ => 1 }  @{ $options->{np_flags} };
	my $result = lfm_np($options->{np_user}, 1);

	return format_output($options->{np_fpattern}, $result);
}

sub uc_tell {
	my $options = shift;
	my $text = shift;

	my @nicks = @{ $options->{highlight} };
	my $nickstring = join(", ", @nicks);
	return format_output("{nicks text:%nicks: %text}", { nicks => $nickstring,
			text => $text});
}

sub process_command {
	my $cmd = shift;
	my $prev = shift;

	if (my $np = $cmd->{np}) {
		return uc_np($np);
	} elsif (my $tell = $cmd->{tell}) {
		return uc_tell($tell, $prev);
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
		} elsif (my $cmdlist = $lfm->{cmdlist} ) {
			# Command List
			my $last;
			foreach my $cmd (@{$cmdlist}) {
				$last = process_command($cmd);
			}
			return $last;
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

