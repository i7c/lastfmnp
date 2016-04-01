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
CONFKEY_NPSTRING_ALBUM = "npstring_album"
CONFKEY_TELLSTRING="tellstring"
CONFKEY_USER = "user"
CONFKEY_WHO = "who"

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
    result = template
    for k,v in kwargs.iteritems():
        if k in REPLACE_MAP:
            result = result.replace(REPLACE_MAP[k], v)
        else:
            weechat.prnt("", "Unknown key: " + k)
    return result

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

"""
    Command to be called by weechat user: /lastfmnp
"""
def lastfmnp(data, buffer, args):
    who = weechat.config_string(weechat.config_get(CONF_PREFIX
        + CONFKEY_WHO))
    message_default = weechat.config_string(weechat.config_get(CONF_PREFIX
        + CONFKEY_NPSTRING))
    message_album = weechat.config_string(weechat.config_get(CONF_PREFIX
        + CONFKEY_NPSTRING_ALBUM))
    msg = ""

    if len(args) > 0:
        # which song is someone else playing (lastfmnp command with argument)
        try:
            np = lastfm_np(args)
        except:
            weechat.prnt("", "last.fm does not respond (timeout)")
            return weechat.WEECHAT_RC_ERROR;
        if np:
            msg = format_message(message_default, who=unicode(args), **np)
    else:
        # which song am I playing?
        try:
            np = lastfm_np()
        except:
            weechat.prnt("", "last.fm does not respond (timeout)")
            return weechat.WEECHAT_RC_ERROR;
        if "album" in np:
            msg = format_message(message_album, who=unicode(who), **np)
        elif np:
            msg = format_message(message_default, who=unicode(who), **np)
        else:
            weechat.prnt("", "lastfmnp: API response was empty or invalid.")
    if msg:
        weechat.command(buffer, msg.encode("utf-8"))
    else:
        weechat.prnt("", "According to last.fm no song is playing right now.")
    return weechat.WEECHAT_RC_OK

def tellnp(data, buffer, args):
    if len(args) < 1:
        weechat.prnt("", "tellnp needs one argument!")
        return weechat.WEECHAT_RC_ERROR;
    who = weechat.config_string(weechat.config_get(CONF_PREFIX
        + CONFKEY_WHO))
    message_tell = weechat.config_string(weechat.config_get(CONF_PREFIX
        + CONFKEY_TELLSTRING))
    np = lastfm_np()
    if np:
        msg = format_message(message_tell, who=unicode(who),
                addressee=unicode(args), **np)
        weechat.command(buffer, msg.encode("utf-8"))
    else:
        weechat.prnt("", "According to last.fm no song is playing right now.")
    return weechat.WEECHAT_RC_OK

"""
    Initialization for Weechat
"""
weechat.register(SCRIPT, "i7c", "0.2", "GPL3",
        "Prints currently playing song from last.fm", "", "")

weechat.hook_command("lastfmnp", "prints currently playing song",
        "[username]", "username: lastfm username", "lastfmnp", "lastfmnp", "")
weechat.hook_command("tellnp", "tells a fellow user the currently playing song",
        "[nick]", "nick: the other user", "tellnp", "tellnp", "")

script_options = {
        CONFKEY_NPSTRING: "[who] np: [artist] - [title]",
        CONFKEY_NPSTRING_ALBUM: "[who] np: [artist] - [title] ([album])",
        CONFKEY_APIKEY: "",
        CONFKEY_USER: "",
        CONFKEY_TELLSTRING: "[addressee]: I'm np: [artist] - [title]",
        CONFKEY_WHO: "/me"}

for option, default in script_options.items():
    if not weechat.config_is_set_plugin(option):
        weechat.config_set_plugin(option, default)

