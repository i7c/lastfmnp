"""
    lastfmnp.py

    author: i7c <i7c AT posteo PERIOD de>
    version: 0.2
    license: GPLv3

LICENSE:
    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.

Description:
    lastfmnp.py can say the currently played song  by a last.fm user to a
    buffer. It requires a valid API key for the last.fm API. This plugin does
    not provide the key, you may obtain one from last.fm.


    np command: /lastfmnp [user]

    If the optional user argument is not provided, it will retrieve the
    currenctly playing song by last.fm user set in
    "plugins.var.python.lastfmnp.user". With one argument it will retrieve the
    song of that user, like so:

    /lastfmnp iSevenC

    With or without optional argument, the script will say the message set in
    the npstring option. The following placeholders are replaced:

    [who] is replaced by either the provided username, or by whatever is set in
    the "plugins.var.python.lastfmnp.who" option. This is usually "/me".

    [title] is replaced by the song title

    [artist] is replaced by the song's artist

    If the last.fm API provides information about the album, lastfmnp uses
    "plugins.var.python.lastfmnp.npstring_album" as template instead.
    Additionally [album] is replaced by the name of the album.


    tell command: /tellnp [nick]

    Works like /lastfmnp, but uses tellstring as message template and replaces
    [addressee] by the provided nick argument.
"""
import weechat
import pylast
import signal

SCRIPT = "lastfmnp"
CONF_PREFIX = "plugins.var.python." + SCRIPT + "."
CONFKEY_APIKEY = "apikey"
CONFKEY_NPSTRING = "npstring"
CONFKEY_ARTISTSTRING="artist_string"
CONFKEY_USER = "user"
CONFKEY_WHO_START = "who.start"
CONFKEY_WHO_MIDDLE = "who.middle"

REPLACE_MAP = {
        "who": u"[who]",
        "title": u"[title]",
        "artist": u"[artist]",
        "album": u"[album]",
        "addressee": u"[addressee]"
        }

"""
    Formats an np string
"""
def format_message(template, **kwargs):
    who=""
    prefix=""
    # select who depending on whether tell is set or not
    # also determine the prefix if tell is set
    if "tell" in kwargs:
        kwargs["who"] = weechat.config_string(weechat.config_get(CONF_PREFIX
            + CONFKEY_WHO_MIDDLE))
        prefix = kwargs["tell"] + ": "
    else:
        kwargs["who"] = weechat.config_string(weechat.config_get(CONF_PREFIX
            + CONFKEY_WHO_START))

    result = template
    for k,v in kwargs.iteritems():
        if k in REPLACE_MAP:
            result = result.replace(REPLACE_MAP[k], v)
    return prefix + result

"""
    Callback for timeout
"""
def _timeout_handler(signum, frame):
    raise IOError("A timeout protected section expired.")

"""
    Start timeout protected section
"""
def timeout_begin():
    signal.signal(signal.SIGALRM, _timeout_handler)
    signal.alarm(2)

"""
    End timeout protected section
"""
def timeout_end():
    signal.alarm(0)

"""
    Obtains and returns last.fm network and user objects of pylast.
    If the API does not respond within given time, an exception is raised.
"""
def obtain_fmuser(who = None):
    api_key = weechat.config_string(weechat.config_get(CONF_PREFIX
        + CONFKEY_APIKEY))
    username = weechat.config_string(weechat.config_get(CONF_PREFIX
        + CONFKEY_USER))

    timeout_begin()
    network = pylast.LastFMNetwork(api_key = api_key)
    if who:
        user = network.get_user(who)
    else:
        user = network.get_user(username)
    timeout_end()
    return (network, user)

"""
    Retrieves the np information for who. If who is not set, retrieve for user
    set in the configuration opitons.
"""
def lastfm_np(who = None):
    npinfo = {}

    net, user = obtain_fmuser(who) 
    timeout_begin()
    np = user.get_now_playing()
    timeout_end()
    if not np:
        return {}
    npinfo["title"] = np.title
    npinfo["artist"] = np.artist.name
    if np.get_album():
        npinfo["album"] = album = np.get_album().get_title()
    return npinfo

def lastfm_top_artist():
    net, user = obtain_fmuser()

    timeout_begin()
    topartist = user.get_top_artists(period=pylast.PERIOD_7DAYS, limit=1)
    timeout_end()
    return topartist[0][0]

"""
    Command to be called by weechat user: /lastfmnp
"""
def subcmd_np(data, buffer, args, **kwargs):
    message_template = weechat.config_string(weechat.config_get(CONF_PREFIX
        + CONFKEY_NPSTRING))
    msg = ""

    try:
        np = lastfm_np()
    except:
        weechat.prnt("", "last.fm does not respond (timeout)")
        return weechat.WEECHAT_RC_ERROR;
    if np:
        np.update(kwargs)
        msg = format_message(message_template, **np)
    else:
        weechat.prnt("", "lastfmnp: API response was empty or invalid.")
    if msg:
        weechat.command(buffer, msg.encode("utf-8"))
    else:
        weechat.prnt("", "According to last.fm no song is playing right now.")
    return weechat.WEECHAT_RC_OK

def subcmd_artist(data, buffer, args, **kwargs):
    message = weechat.config_string(weechat.config_get(CONF_PREFIX
        + CONFKEY_ARTISTSTRING))

    artist = lastfm_top_artist()
    if artist:
        msg = format_message(message, artist=artist.get_name(), **kwargs)
        weechat.command(buffer, msg.encode("utf-8"))
    else:
        weechat.prnt("", "Unexpected error from last.fm")
    return weechat.WEECHAT_RC_OK

def _match_token(token, args):
    if args[0] == token:
        args.pop(0)
        return True
    else:
        return False

def subcmd_weekly(data, buffer, args, **kwargs):
    if _match_token("artist", args):
        return subcmd_artist(data, buffer, args, **kwargs)
    else:
        weechat.prnt("", "lastfmnp: Unknown subcommand " + args[0])
        return weechat.WEECHAT_RC_ERROR;

"""
    /lfm command that takes arguments and does all the things!
"""
def cmd_lfm(data, buffer, args):
    options = {}
    args = args.split()

    if _match_token("tell", args):
        options["tell"] = args.pop(0)
    if _match_token("np", args):
        return subcmd_np(data, buffer, args, **options)
    elif _match_token("weekly", args):
        return subcmd_weekly(data, buffer, args, **options)
    else:
        weechat.prnt("", "lastfmnp: Unknown command " + args[0])
        return weechat.WEECHAT_RC_ERROR;
    return weechat.WEECHAT_RC_OK


"""
    Initialization for Weechat
"""
weechat.register(SCRIPT, "i7c", "0.2", "GPL3",
        "Prints currently playing song from last.fm", "", "")

weechat.hook_command("lfm",
        "/lfm performs all kind of last.fm actions in your buffer.\n\n"
        "Available commands:\n"
        "* np        shows currently playing song\n"
        "* weekly    shows your weekly favourites\n\n"
        "You can prefix your command with tell <nick> to highlight someone.",
        "",
        "",
        "np %-"
        "|| weekly artist"
        "|| tell %(nick) np|weekly artist",
        "cmd_lfm", "")

script_options = {
        CONFKEY_NPSTRING: "[who] listening to [artist] - [title]",
        CONFKEY_APIKEY: "",
        CONFKEY_USER: "",
        CONFKEY_WHO_START: "/me",
        CONFKEY_WHO_MIDDLE: "I'm",
        CONFKEY_ARTISTSTRING: "My artist of the week is [artist]."}

for option, default in script_options.items():
    if not weechat.config_is_set_plugin(option):
        weechat.config_set_plugin(option, default)

