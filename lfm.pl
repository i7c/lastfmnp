use Regexp::Grammars;
use Data::Dumper;
use LWP::UserAgent;
use JSON;
use strict;
use warnings;

use constant BASE_URL => 'https://ws.audioscrobbler.com/2.0/?';
my $apikey = "";

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

sub lfm_np {
	my $user = shift;
	return lfmjson("user.getRecentTracks", {user => $user});
}


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


	# Tell Command
	<rule: tell> <[highlight]>+

	# NP Command
	<rule: np>
		np <[np_flags]>* <np_user=(\w+)>? ("<np_fpattern>")?

	<rule: np_flags>
		(-n|--np-only)(?{$MATCH="PLAYING";})

	<rule: np_fpattern>
		[^"]+

	# Names
	<rule: highlight> @<name> (?{ $MATCH=$MATCH{name}; })
	<rule: name> [a-zA-Z0-9_`\[\]]+

};

sub command_np {
	my $options = shift;
	my %flags = map { $_ => 1 }  @{ $options->{np_flags} };

	my $apires = lfmjson("user.getRecentTracks",
		{user => $options->{np_user}, limit => 1 });

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

	if ($flags{PLAYING} && ! $data->{active}) {
		# Do nothing if not active and -n is set
		return "";
	}


	print Dumper($data);
}

sub process_command {
	my $cmd = shift;
	my $prev = shift;

	if ($cmd->{np}) {
		return command_np($cmd->{np});
	} elsif ($cmd->{tell}) {
	}

}

sub process_input {
	my $input = shift;

	if ($input =~ $lfmparser) {
		my $lfm = $/{lfm};
		#print Dumper($lfm);

		if (my $cmdchain = $lfm->{cmdchain} ) {
			# Command Chain
			my $previous = "";
			foreach my $cmd (@{$cmdchain}) {
				$previous = process_command($cmd, $previous);
			}
		} elsif (my $cmdlist = $lfm->{cmdlist} ) {
			# Command List
			foreach my $cmd (@{$cmdlist}) {
				process_command($cmd);
			}
		} else {
			#TODO: error case
		}
	} else {
		# Handle error
	}
}


process_input($ARGV[0]);
