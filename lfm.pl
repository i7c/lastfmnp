use Regexp::Grammars;
use Data::Dumper;
use LWP::UserAgent;
use JSON;
use Digest::MD5 qw(md5_hex);
use strict;
use warnings;

use constant BASE_URL => 'https://ws.audioscrobbler.com/2.0/?';
my $prgname = "lfm";
my $confprefix = "plugins.var.perl.$prgname";
my $weechat = 1;

my $LFMHELP =

"$prgname.pl is a weechat plugin that allows to query the last.fm-API in
several ways and 'say' the results to current buffers.  $prgname.pl adds one
command to weechat called /$prgname, which accepts a 'command chain' as argument.

While previous versions of this script only provided access to high-level
commands, this version exposes all the internal commands to the user as well and
allows to define own commands. Usually, the user has all means to 'rewrite' the
high-level commands and of course create new useful high-level commands with
these means. In the following we describe all available commands and language
features.

COMMAND CHAIN AND INPUT/OUTPUT REDIRECTION
******************************************

A 'command chain' (which can have the length of one, i.e. a single command, of
course) is a list of commands separated either by pipes (|) or semicolons (;).
Both separators are equivalent. The commands are executed from left to right and
the result of any command is passed to the next command by default. This allows
for 'processing pipelines': /$prgname cmd1 | cmd2 | cmd3 ...

The result of the last command is posted to the current buffer. Sometimes it
might be desirable to prevent a command from passing its result to the next
command in the command chain (or the buffer). In that case you can use a ^ at
the end of the command to redirect the output to nowhere.

In earlier versions you had to use subshells to redirect input and output from
and to variables, as in \$ inputVar {cmd1 | cmd2 | cmd3 } outputVar; Now the
commands themselves support redirection to and from variables. You can use the
redirection operators < and > to specify source and destination. E.g. the above
example would look like this: cmd1 <inputVar | cmd2 | cmd3 >outputVar;

There can be *many* output redirectors:

cmd >var1 >var2

which will cause the output of cmd being stored in both var1 and var2. But there
is only *one* input redirector. The input redirector must be before the output
redirectors. So the general syntax is summed up as:

<command> [<invar] [>outvar ...] [^]

The use of the output redirector will not consume the output of the command, so
even if you use >var you still need to use the ^ operator to silence the
command.

The 'old' way to store output in vars with subshells (\${}) can still be used
with the special env variable on the output (\${command} env;), but for all
other cases the redirectors are the preferred method.

CONFIGURATION
*************
There are some essential configuration options which the user must set. Below
we describe this minimal setup. Note, that the script now provides an automatic
way to create all configuration options. You can use /$prgname conf --default
the first time you run the script and everytime it is updated. It will leave
existing configurations untouched and save default values for new options. You
can use iset (or plain old /set) to adapt the config. Some values must be
provided by the user, such as apikey, secret, user. conf --default will leave
them empty. conf --default creates all known keys, if you prefer a minimal
automatic setup, use the --minimal flag instead. For more information refer to
the section about the conf command below.

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
if you set /set plugins.var.perl.$prgname.alias.comp_artist to a valid
command chain as value, you effectifely created the alias comp_artist.

You can execute the alias exactly as any other command by running:

/$prgname !comp_artist

The ! *may* be ommitted if it is still unambigious that you are
referring to an alias. If in doubt, just add the ! in front. Aliases
can be used in command chains just like normal commands:

/$prgname !comp_artist | dump

Aliases can take positional arguments. Say you create the following alias

/set plugins.var.perl.$prgname.alias.xtracks \"utracks -u \$1 -n \$2\"

you can use the alias with arguments: /$prgname !xtracks iSevenC 3

Arguments can be single words (or numbers for that matter) or
single-quoted strings. Please note that alias arguments are simple
string replacements that happen *before* the alias is executed. Alias
arguments can only be literal and not the evaluation of some complex
term. If you pass a single word the respective \$x will be replaced by
that word. If you pass 'a single quoted string' the \$x will be replaced
by that string *including* the ''. In most cases this is what you want.
Because aliases work with simple string-based expansion, you can even
do things like

/set plugins.var.perl.$prgname.alias.test \"utracks | \$1\"

/$prgname !test dump

If you want to replace \$x by a string (more than one word) but
without any '' you can use [ ]. Examples:

/set plugins.var.perl.$prgname.alias.test \"utracks \$1\"

/$prgname !test [| dump]

AUTHORIZATION
*************

For API calls that require authentication, you need to retrieve a session key
from last.fm first. Note that you must set both the 'apikey' and the 'secret'
option for this to work. Both values for these options are provided by last.fm
when you create an API key. If both values are set, in almost all cases this
will suffice to configure the required session key:

1. /$prgname auth
2. click link and auth
3. /$prgname session
4. ???
5. if all worked fine without errors: PROFIT

COMMANDS
********

np [-u|--user <user>] [-p|--pattern <format pattern>] [<flags>]

    Prints the currently played or (if not available) the most
    recently played song.

    You may specify a user with -u. If no user is specified the
    environment variable 'user' will be read. If it is not set either,
    the value from the option $confprefix.user is used.

    You can specify a format pattern. If you don’t, the pattern set in
    $confprefix.pattern.np will be used. np uses the format function to produce
    the output. It automatically sets two format variables: %who and %me. If np
    retrieved information for a different user (i.e. if -u or the variable were
    set) then %who is set to this user, otherwise it is set to the value from
    $confprefix.who. %me behaves similar, but it defaults to '/me'.

    Flags:
    -n:  Only return result if song is currently playing
    -t:  Only return the title of the song (overrides format pattern)
    -a:  Only return the artist of the song (overrides format pattern)
    -A:  Only return the album of the song (overrides format pattern)

    You can specify only one of -t -a or -A (or undefined shit happens).

utracks [-u|--user <user>] [-n|--number <number>]

    Retrieves recently played tracks from a user.

    You may specify a user explicitly with -u or supply one by using the
    environment variable 'user'. If none of those are specified, it defaults
    to whatever is set in $confprefix.user.

    You can request a certain number of recent tracks by using -n. Please note
    the limitations given by the last.fm-API. This defaults to 10. You can also
    use the environment variable 'num' for this option.

    The result of this operation is json so you can access it with filter and
    similar functions. Note also the special commands 'take' and
    'extrackt track' which can be useful here.

uatracks [-u|--user <user>] [-a|--artist <artist>]

    This command is much like utracks, but it lets you specify an artist so
    only tracks of a certain artist are retrieved. The artist can be specified
    with -a or with the environment variable 'artist'.

    Example: retrieve all played tracks by the currently played artist which
    user xyz scrobbled:

    /$prgname \${np -a} artist; uatracks -u xyz

    Just like utracks, the result is json.

user [-u|--user <user>]

    Retrieves basic user information from last.fm. The result is json. If you
    don’t specify -u, it will retrieve your information from last.fm

artist [-a|--artist <artist>] [-u|--user <user>] [-l|--lang <language>] [-i|--id <id>]

    Retrieves basic information about an artist. The response is json.

    You can specify the artist with -a aristname. If it contains spaces
    use -a 'Artistname with spaces'. If -a is not specified, the command reads
    from stdin or from the environment variable 'artist'.
    Instead of -a you can use -i with a musicbrainz id as argument.

    If you specify -u, the response will contain personal stats for that user,
    such as the playcount. Without the -u option, this defaults to yourself
    ($confprefix.user).

    The -l option sets the language for the response. It is simply passed to
    the last.fm-API, I have no idea how many languages are supported. (en, de,
    es, pt work at least).

take <n>

    takes an array from stdin and returns the n-th element on stdout

extract user|track

    This is a convenient shortcut for some frequent filter invocations. It’s
    often the same bits you want to extract from a response.

    extract user takes a user object of a last.fm-response and returns a flat
    hash (only one level of key-value-pairs, no nesting) on stdout.

    extract track does the same for track objects.

    Example: reimplement the np command:

    utracks -n 1 | take 0 | extract track
        | format '{artist title:/me is playing %artist - %title}' 

filter <filter-pattern>...

    filter takes a json object on stdin (with arbitrary deep nesting) and
    extracts parts of it, providing a *flat* hash on stdout. You can specify
    a list of comma-separated filter patterns, each pattern looking like this:

        original.value -> newname

    Consider this part of a utracks response:

    [
      {
        'name' => 'You Were But a Ghost in My Arms',
        'mbid' => '592d0ea5-fe50-4f8a-adb9-cc16d1d766bf',
        'streamable' => '0',
        'artist' => {
                      '#text' => 'Agalloch',
                      'mbid' => '3d46727d-9367-47b8-8b8b-f7b6767f7d57'
                    },

        ...
      }
    ]


    This is an array of objects. Now say you want to extract the artist mbid
    and call the new key 'id'. You could apply filter as follows:

    filter 0.artist.mbid -> id

format '<format-pattern>'

    format takes a flat hash as input and produces a formatted string using the
    values from the hash. The format pattern consists of groups (as many as
    you like). A group is surrounded by {} und looks roughly like this:

    {<var preconditions>:<format-string>}

    In the var preconditions section you can put a (space-separated) list of
    variables. The entire group will only be part of the output if *all* these
    variables are defined. The list can be empty.

    The format-string section is a string that will be literally copied to the
    output except for variables prefixed with a %, which will be replaced by
    their values.

    Groups *cannot* be nested.

    It’s best explained with a bunch of examples:

    {:This will always be printed}

    output: This will always be printed

    {artist title:The song %title is by %artist}

    Assuming both artist and title are defined with values 'Hodor' and 'hodor',
    the output is: The song hodor is by Hodor

    The variables from the preconditions list can be used several times:

    {h:%h%h%h}

    Assuming h is 'hodor': hodorhodorhodor

    or not used at all:

    {album:I have album information but I won’t tell you}

    This is a good example for the usage of multiple groups:

    {artist title me:%me is playing %artist - %title}{artist title album: (%album)}

@ <names>...

    @ (also dubbed the 'tell-command') can be used to highlight other users. By
    using the output of any other command. It uses the config option

    $confprefix.pattern.tell

    as format pattern. You can (should) use the 'nicks' and 'text' variables in
    the pattern. We assume this pattern for examples:

    {nicks text:%text ← %nicks}

    /lfm np | @ Hodor

    might lead to something like: /me is playing Herp - Derp ← Hodor

    You can name as many nicks as you wish:

    /lfm love | @ herp derp hodor foo bar

love [-q|--quiet]

    Requires configured auth

    This command loves the currently playing song (or most recently played).
    If -q is specified loves the song quietly. If not it will say a message
    to the current buffer using the format pattern in

    $confprefix.pattern.love

    The variables %title and %artist are provided.

hate [-q|--quiet]

    Requires configured auth

    Unloves a song. Without quiet say a message to the buffer using the pattern

    $confprefix.pattern.hate

    The variables %title and %artist are provided.

asearch [-n|--num <number>] [-p|--page <number>] <artist>

    Performs an artist search on last.fm. You can limit the number of results
    with -n (defaults to 5) and retrive the n-th page using -p n.
    <artist> can be a single word or a 'single quoted string'.

    Returns json.

tsearch [-n|--num <number>] [-p|--page <number>] <track>

    Performs a track search on last.fm. You can limit the number of results
    with -n (defaults to 5) and retrive the n-th page using -p n.
    <track> can be a single word or a 'single quoted string'.

    Returns json.

select <path>

    select is like filter but it extracts a single value. The result is a value,
    not a flat hash. (Of course the result can be a hash if you select a single
    hash)

    Consider following json object:

    [
      {
        'name' => 'You Were But a Ghost in My Arms',
        'mbid' => '592d0ea5-fe50-4f8a-adb9-cc16d1d766bf',
        'streamable' => '0',
        'artist' => {
                      '#text' => 'Agalloch',
                      'mbid' => '3d46727d-9367-47b8-8b8b-f7b6767f7d57'
                    },

        ...
      }
    ]


    select 0.artist.mbid

    returns 3d46727d-9367-47b8-8b8b-f7b6767f7d57

amap <subshell>

    amap is a simple yet powerful command. It takes only an array as input and
    produces an array as output. You must specify a subshell. If you specify
    invars or outvars for the subshell, they will be ignored. amap will strip
    the variables from the subshell. Only the command chain matters. If you use
    a nested subshell inside the command chain, it will work as expected (with
    variables).

    amap will execute the command chain once for each entry in the array and
    will provide this entry as input for the first command. The result of the
    chain will be stored in the result array.

    Example invocation:

    asearch 'horse' | select results.artistmatches.artist | amap \${select name} | dump

    Result:

    \$VAR1 = [
              'Band of Horses',
              'HORSE the band',
              'Horse Feathers',
              '16 Horsepower',
              'Neil Young & Crazy Horse'
            ];

auth

    This command is the first step for authentication against the last.fm API.
    It takes no arguments. It initiates a new authentication process and will
    result in a API token and print a matching link on the weechat buffer. You
    have to click this link to authorize the the token *before* you move on to
    the next step. Once you have completed authorization, you may call the
    session command.

session [-t|--token <token>]

    This is the second step for authorization. *After* you completed the
    authorization of the token (see /$prgname auth) you may call /lfm session.
    You can (usually you don’t) specify the token using -t. If you don’t
    specify it, the command will assume the most recently retrieved token. This
    only works if you used /$prgname auth for the first step of authorization.

conf [--minimal|--default] [--reset] [--verbose]

    This generates a default config as far as possible. That is, it makes all
    the config options but some will be left empty (the api key for example).
    Use the iset script or similar to set all values.

    --minimal only creates the options which are absolutely necessary to use
    /$prgname, especially the /$prgname np command.

    --default creates all known options that the user can set.

    If you specify --reset, conf will overwrite existing options with their
    default value *unless* the default value is empty (for example in case of
    the api key, --reset will not delete your api key because there is no real
    default value for it).

    If you specify --verbose, conf tells you about options it *would* set if
    you specified --reset.

    If you want to reset a single option, unset it manually and run
    conf --default *without* the --reset option.

dump

    Takes anything as input and dumps it to the weechat buffer. This is very
    useful to debug own commands (or chains) and see their result. dump
    provides no output.

    Example:
    /$prgname user | dump
";

binmode(STDOUT, ":utf8");

my %env = ();


#### Platform Abstraction Stuff  ####
sub lfm_print {
    my $buffer = shift;
    my $what = shift;

    if ($weechat) {
        weechat::command($buffer, $what);
    } else {
        #default to stdout
        print $what;
    }
}

sub lfm_error {
    my $what = shift;

    if ($weechat) {
        weechat::print("", "[lfm error] $what");
    } else {
        #default to stdout
        print STDERR "[lfm error] $what";
    }
}

sub lfm_info {
    my $what = shift;

    if ($weechat) {
        weechat::print("", "[lfm info] $what");
    } else {
        #default to stdout
        print STDERR "[lfm info] $what";
    }
}

sub weechat_only {
    if (! $weechat) {
        lfm_error("Cannot perform this action unless running as weechat plugin.");
        exit 1;
    }
}

sub cnf {
    my $option = shift;
    return weechat::config_get("$confprefix.$option");
}

sub cnf_set_default {
    my $option = shift;
    my $default = shift;
    my $overwrite = shift;
    my $verbose = shift;

    if (! weechat::config_is_set_plugin($option)) {
        if (! $default) { $default = ""; }
        weechat::config_set_plugin($option, $default);
        lfm_info("Set $confprefix.$option = $default");
    } elsif ($overwrite) {
        if ($default) {
            weechat::config_set_plugin($option, $default);
            lfm_info("Set $confprefix.$option = $default");
        }
    } elsif ($default && $verbose) {
        lfm_info("Would set: $confprefix.$option = $default");
    }
}

sub load_alias {
    my $name = shift;
    my $weechat_home = weechat::info_get("weechat_dir", "");
    my $path = weechat::config_string(cnf("path.alias"));
    $path =~ s/%h/$weechat_home/;
    $path .= "/$name";
    my $input;
    if (-e $path) {
        local $/=undef;
        open FILE, $path;
        $input = <FILE>;
        close FILE;
    } else {
        lfm_error("Error: alias file not found: $path");
        return "";
    }
    return $input;
}

sub bind_alias {
    my $alias = shift;
    my $args = shift;

    for (my $i = scalar @{$args}; $i > 0; $i--) {
        my $arg = $args->[$i - 1]->{arg};
        $alias =~ s/\$$i/$arg/g;
    }
    return $alias;
}

sub sign_call {
    my $method = shift;
    my $params = shift;
    my $apikey = weechat::config_string(cnf("apikey"));
    my $secret = weechat::config_string(cnf("secret"));

    my @parts = ("api_key$apikey", "method$method");
    foreach my $key (keys %$params) {
        push @parts, "$key" . $params->{$key};
    }
    my @sorted = sort @parts;
    my $str = join("", @sorted) . $secret;
    return md5_hex($str);
}

sub lfmjson {
    my $method = shift;
    my $params = shift;
    my $sign = shift;
    my $auth = shift;

    my $apikey = weechat::config_string(cnf("apikey"));
    my $ua = LWP::UserAgent->new;
    $ua->agent("lastfmnp/0.0");
    if ($auth) {
        my $sk = weechat::config_string(cnf("sk"));
        $params->{"sk"} = $sk;
    }
    if ($sign) {
        my $signature = sign_call($method, $params);
        $params->{"api_sig"} = $signature;
    }

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
        | <love>
        | <hate>
        | <asearch>
        | <tsearch>
        | <select>
        | <amap>
        | <join>
        | <cp>
        | <auth>
        | <session>
        | <conf>
        | <subshell>
        | <variable>
        | <alias>)
        (\< <fromvar=name>)? (\> <[tovar=name]>+ % \>)?  <tonowhere=(\^)>?


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
        user
        (
            (-u|--user) <name>
        )* <ws>

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

    <rule: love>
        love
        (
            <quiet=(-q|--quiet)>
        )* <ws>

    <rule: hate>
        hate
        (
            <quiet=(-q|--quiet)>
        )* <ws>

    <rule: asearch>
        asearch
        (
            (-n|--num) <num=number>
            | (-p|--page) <page=number>
        )* <ws> (<artist=name> | '<artist=str>')?

    <rule: tsearch>
        tsearch
        (
            (-n|--num) <num=number>
            | (-p|--page) <page=number>
        )* <ws> (<track=name> | '<track=str>')?

    <rule: select>
        select <from=name>

    <rule: amap>
        amap <by=subshell>

    <rule: join>
        join (<sep=name> | '<sep=str>')

    <rule: cp>
        cp

    <rule: auth>
        auth

    <rule: session>
        session
        (
            (-t|--token) <token=name>
        )* <ws>

    <rule: conf>
        conf
        (
            <minimal=(--minimal)>
            | <default=(--default)>
            | <reset=(--reset)>
            | <verbose=(--verbose)>
        )* <ws>

    <rule: subshell>
        \$ <in=name>? { <sublfm=lfm> } <out=name>?

    <rule: variable>
        let <var=name> = ('<value=str>' | <value=name> | <value=number>)

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

sub lfm_auth_get_token {
    my $apires = lfmjson("auth.getToken", {}, 1);
    return $apires->{token};
}

sub lfm_auth_get_session {
    my $token = shift;
    my $apires = lfmjson("auth.getSession", {token => $token}, 1);
    return $apires->{session}->{key};
}

sub lfm_track_love {
    my $artist = shift;
    my $track = shift;

    my $apires = lfmjson("track.love", {artist => $artist, track => $track},
        1, 1);
    return $apires;
}

sub lfm_track_hate {
    my $artist = shift;
    my $track = shift;

    my $apires = lfmjson("track.unlove", {artist => $artist, track => $track},
        1, 1);
    return $apires;
}

sub lfm_artist_search {
    my $params = shift;

    my $apires = lfmjson("artist.search", $params);
    return $apires;
}

sub lfm_track_search {
    my $params = shift;

    my $apires = lfmjson("track.search", $params);
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
    my $user = $options->{np_user} // $env{user}
        // weechat::config_string(cnf("user"));
    my $fpattern = $options->{np_fpattern} // weechat::config_string(cnf("pattern.np"));

    my $result =
        extract_track_info(array_take(
                lfm_user_get_recent_tracks($user, 1), 0));
    $result->{who} = $options->{np_user} // $env{user}
        // weechat::config_string(cnf("who"));
    $result->{me} = $options->{np_user} // $env{user} // "/me";

    if ($flags{"PLAYING"} && ! $result->{active}) { return ""; }

    $fpattern = "{album:%album}" if ($flags{"ALBUM"});
    $fpattern = "{title:%title}" if ($flags{"TITLE"});
    $fpattern = "{artist:%artist}" if ($flags{"ARTIST"});

    return format_output($fpattern, $result);
}

sub uc_user_recent_tracks {
    my $options = shift;
    my $user = $options->{user} // $env{user}
        // weechat::config_string(cnf("user"));
    my $number = $options->{number} // $env{num} // 10;
    return lfm_user_get_recent_tracks($user, $number);
}

sub uc_user_artist_tracks {
    my $options = shift;
    my $previous = shift;

    my $user = $options->{user} // $env{user}
        // weechat::config_string(cnf("user"));
    my $artist = $options->{artist} // $previous // $env{artist};
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
    $params->{artist} = $options->{artist} // $previous // $env{artist};
    $params->{user} = $options->{user} // $env{user}
        // weechat::config_string(cnf("user"));
    $params->{lang} = $options->{lang} // $env{lang};
    $params->{id} = $options->{id} // $env{id};

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
    lfm_info(Dumper($data));
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

sub uc_love {
    my $params = shift;
    shift; # ignore previous

    my $user = $env{user} // weechat::config_string(cnf("user"));
    my $result = extract_track_info(array_take(
            lfm_user_get_recent_tracks($user, 1), 0));
    my $succ = lfm_track_love($result->{artist}, $result->{title});

    if (! $succ) {
        lfm_error("love command failed! API response:");
        lfm_error(Dumper($succ));
    }
    if (! $params->{quiet}) {
        my $fpattern = weechat::config_string(cnf("pattern.love"));
        return format_output($fpattern, $result);
    }
    return "";
}

sub uc_artist_search {
    my $options = shift;
    my $previous = shift;

    my $params = {};
    $params->{artist} = $options->{artist} // $previous // $env{artist};
    $params->{limit} = $options->{num} // $env{num} // 5;
    $params->{page} = $options->{page} // $env{page} // 1;
    return lfm_artist_search($params);
}

sub uc_track_search {
    my $options = shift;
    my $previous = shift;

    my $params = {};
    $params->{track} = $options->{track} // $previous // $env{track};
    $params->{limit} = $options->{num} // $env{num} // 5;
    $params->{page} = $options->{page} // $env{page} // 1;
    return lfm_track_search($params);
}

sub uc_select {
    my $options = shift;
    my $data = shift;

    my @pattern = ({from => $options->{from}, to => "result"});
    return filter($data, \@pattern)->{result};
}

sub uc_amap {
    my $options = shift;
    my $data = shift;

    my $result = [];
    foreach my $entry (@{$data}) {
        my $res = process_cmdchain($options->{by}->{sublfm}->{cmdchain},
            $entry);
        push @{$result}, $res;
    }
    return $result;
}

sub uc_join {
    my $options = shift;
    my $data = shift;
    return join($options->{sep}, @{$data});
}

sub uc_cp {
    my $options = shift;
    my $input = shift;
    return $input;
}

sub uc_hate {
    my $params = shift;
    shift; # ignore previous

    my $user = $env{user} // weechat::config_string(cnf("user"));
    my $result = extract_track_info(array_take(
            lfm_user_get_recent_tracks($user, 1), 0));
    my $succ = lfm_track_hate($result->{artist}, $result->{title});

    if (! $succ) {
        lfm_error("unlove command failed! API response:");
        lfm_error(Dumper($succ));
    }
    if (! $params->{quiet}) {
        my $fpattern = weechat::config_string(cnf("pattern.hate"));
        return format_output($fpattern, $result);
    }
    return "";
}

sub uc_auth {
    my $options = shift;
    shift; # ignore previous

    my $token = lfm_auth_get_token();
    my $apikey = weechat::config_string(cnf("apikey"));

    lfm_info("xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx");
    lfm_info("Received token: $token");
    lfm_info("Visit https://www.last.fm/api/auth/?api_key=$apikey&token=$token");
    lfm_info("xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx");

    weechat::config_set_plugin("token", $token);
    return "";
}

sub uc_session {
    my $options = shift;
    shift; # ignore previous

    my $token = $options->{token} // weechat::config_string(cnf("token"));
    lfm_info("Retrieving session key from last.fm ...");
    lfm_info("Using token: $token");
    my $sk = lfm_auth_get_session($token);
    weechat::config_set_plugin("sk", $sk);
    lfm_info("Session key saved.");
    return "";
}

sub uc_conf {
    my $options = shift;
    shift; # ignore previous

    weechat_only;

    my $force = $options->{reset};
    my $verbose = $options->{verbose};
    if ($options->{minimal} || $options->{default}) {
        cnf_set_default("apikey", undef, $force, $verbose);
        cnf_set_default("user", undef, $force, $verbose);
        cnf_set_default("pattern.np",
            "{artist title me:%me is playing %artist - %title}"
            . "{artist title album: (%album)}",
            $force, $verbose);
        cnf_set_default("pattern.tell", "{nicks text:%text ← %nicks}",
            $force, $verbose);
        cnf_set_default("who", "/me", $force, $verbose);
    }
    if ($options->{default}) {
        cnf_set_default("secret", undef);
        cnf_set_default("pattern.hate",
            "{artist title:I unloved %artist - %title!}", $force, $verbose);
        cnf_set_default("pattern.love",
            "{artist title:I love %artist - %title!}", $force, $verbose);
        cnf_set_default("path.alias", "%h/lfm", $force, $verbose);
    }
    return "";
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
                lfm_error("lfm: tried to embed something other than hash in environment");
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
    $env{$options->{var}} = $value;
    return $value;
}

sub uc_alias {
    my $options = shift;
    my $previous = shift;

    my $input = load_alias($options->{name});
    if (! $input) { return; }
    if ($options->{args}) {
        $input = bind_alias($input, $options->{args});
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
        "love" => \&uc_love,
        "hate" => \&uc_hate,
        "asearch" => \&uc_artist_search,
        "tsearch" => \&uc_track_search,
        "select" => \&uc_select,
        "amap" => \&uc_amap,
        "join" => \&uc_join,
        "cp" => \&uc_cp,
        "auth" => \&uc_auth,
        "session" => \&uc_session,
        "conf" => \&uc_conf,
        "subshell" => \&uc_subshell,
        "variable" => \&uc_variable,
        "alias" => \&uc_alias,
    );

    for my $key (keys %{ $cmd } ) {
        if ($key && $callmap{$key}) {
            $prev = $env{$cmd->{fromvar}} if ($cmd->{fromvar});
            my $result = $callmap{$key}->($cmd->{$key}, $prev);
            # possibly redirect result to variables
            if ($cmd->{tovar}) {
                for my $var (@{$cmd->{tovar}}) {
                    $env{$var} = $result;
                }
            }
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
        lfm_error("Input error");
    }
}

sub lfm {
    my $data = shift;
    my $buffer = shift;
    my $args = shift;

    %env = ();
    $env{env} = \%env;
    lfm_print($buffer, process_input($args));
}

sub dumpast {
    my $data = shift;
    my $buffer = shift;
    my $args = shift;

    if ($args =~ $lfmparser) {
        my $lfm = $/{lfm};
        lfm_info(Dumper($lfm));
        if (my $cmdchain = $lfm->{cmdchain} ) {
            # Command Chain
            foreach my $cmd (@{$cmdchain}) {
                if ($cmd->{"alias"}) {
                    lfm_info("Dumping AST for alias " . $cmd->{alias}->{name});
                    my $input = load_alias($cmd->{alias}->{name});
                    $input = bind_alias($input, $cmd->{alias}->{args});
                    dumpast($data, $buffer, $input);
                }
            }
        }
    } else {
        lfm_error("No valid input. No AST available.");
    }
}

if ($ARGV[0] && $ARGV[0] =~ /cli/i) {
    $weechat = 0;
    print process_input($ARGV[1]);
} else {
    weechat::register("lfm", "i7c", "0.3", "GPL3", "Prints last.fm shit", "", "");
    weechat::hook_command("lfm", $LFMHELP,
        "lfm",
        "",

        "np || utracks || uatracks || user || artist || take || extract "
        . "|| filter || format || dump || tell || track || love || hate "
        . "|| auth || session || conf || subshell || variable || alias",

        "lfm",
        "");
    weechat::hook_command("dumpast", "dumps lastfm shit",
        "dumpast",
        "",
        "",
        "dumpast", "");
}

