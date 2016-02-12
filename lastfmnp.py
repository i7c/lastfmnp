"""
    lastfmnp.py

    author: i7c <i7c AT posteo PERIOD de>
    version: 0.1
    license: GPLv3

Description:
    lastfmnp.py can say the currently played song  by a last.fm user to a
    buffer. It requires a valid API key for the last.fm API. This plugin does
    not provide the key, you may obtain one from last.fm.

    lastfmnp.py provides one command: /lastfmnp

    If no argument is provided, it will retrieve the currenctly playing song by
    last.fm user set in "plugins.var.python.lastfmnp.user". With one argument
    it will retrieve the song of that user, like so:

    /lastfmnp iSevenC

    The script will say the message set in the npstring option if a song is and
    the message in the nothing option otherwise. [who], [artist] and [title]
    are replaced by the respective values ([who] being "/me" or the user you
    queried). In the nothing message, only [who] is replaced.
"""
import weechat
import pylast

SCRIPT = "lastfmnp"
CONF_PREFIX = "plugins.var.python." + SCRIPT + "."
CONFKEY_APIKEY = "apikey"
CONFKEY_NPSTRING = "npstring"
CONFKEY_NPSTRING_ALBUM = "npstring_album"
CONFKEY_USER = "user"
CONFKEY_NOTHING = "nothing"

"""
    Formats an np string, depending on the information available
"""
def format_np(who, artist, title, album = None):
    message = weechat.config_string(weechat.config_get(CONF_PREFIX
        + CONFKEY_NPSTRING))
    message_album = weechat.config_string(weechat.config_get(CONF_PREFIX
        + CONFKEY_NPSTRING))
    nothing = weechat.config_string(weechat.config_get(CONF_PREFIX
        + CONFKEY_NOTHING))
    replace_map = {u"[who]": who,
            u"[artist]": artist,
            u"[title]": title}
    result = message
    if album:
        replace_map[u"[album]"] = album
        result = message_album

    for k, v in replace_map.items():
        result = result.replace(k, v)
    return result

"""
    Says the retrieved np information to the buffer.
"""
def sayit(who, np, buffer):
    if np:
        title = np.title
        artist = np.artist.name
        album = None
        if np.get_album():
            album = np.get_album().get_title()
        say = format_np(who, artist, title, album)
    else:
        say = unicode(nothing)
        say = saystr.replace(u"[who]", who)
    if len(say) > 0:
        weechat.command(buffer, say.encode("utf-8"))

"""
    Command to be called by weechat user: /lastfmnp
"""
def lastfmnp(data, buffer, args):
    api_key = weechat.config_string(weechat.config_get(CONF_PREFIX
        + CONFKEY_APIKEY))
    username = weechat.config_string(weechat.config_get(CONF_PREFIX
        + CONFKEY_USER))

    network = pylast.LastFMNetwork(api_key = api_key)
    if len(args) > 0:
        user = network.get_user(args)
        np = user.get_now_playing()
        sayit(unicode(args), np, buffer)
    else:
        user = network.get_user(username)
        np = user.get_now_playing()
        sayit(u"/me", np, buffer)
    return weechat.WEECHAT_RC_OK


"""
    Initialization for Weechat
"""
weechat.register(SCRIPT, "i7c", "0.1", "GPL3",
        "Prints currently playing song from last.fm", "", "")

weechat.hook_command("lastfmnp", "prints currently playing song",
        "[username]", "username: lastfm username", "lastfmnp", "lastfmnp", "")

script_options = {
        CONFKEY_NPSTRING: "[who] np: [artist] - [title]",
        CONFKEY_NPSTRING_ALBUM: "[who] np: [artist] - [title] ([album])",
        CONFKEY_APIKEY: "",
        CONFKEY_USER: "",
        CONFKEY_NOTHING: "[who] is not playing anything right now."}

for option, default in script_options.items():
    if not weechat.config_is_set_plugin(option):
        weechat.config_set_plugin(option, default)
