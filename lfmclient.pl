use LWP::UserAgent;
use JSON;
use strict;
use warnings;

use constant BASE_URL => 'https://ws.audioscrobbler.com/2.0/?';
my $apikey = "";

sub lfm_rq_json {
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
}


my $derp = lfm_rq_json("user.getFriends", {user => "iSevenC"});
