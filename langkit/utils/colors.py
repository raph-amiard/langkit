from contextlib import contextmanager
import sys


try:
    import gdb
except ImportError:
    gdb = None


class Colors(object):
    """
    Utility escape sequences to color output in terminal.
    """
    ENDC = '\033[0m'
    BOLD = '\033[1m'

    RED = '\033[31m'
    GREEN = '\033[32m'
    YELLOW = '\033[33m'
    BLUE = '\033[34m'
    MAGENTA = '\033[35m'
    CYAN = '\033[36m'
    GREY = '\033[97m'

    HEADER = MAGENTA
    OKBLUE = BLUE
    OKGREEN = GREEN
    WARNING = YELLOW
    FAIL = RED

    _enabled = True

    @classmethod
    def disable_colors(cls):
        """
        Disable the use of colors in col/printcol.
        """
        cls._enabled = False


# Keep colors when we are running under GDB. Otherwise, disable colors as soon
# as one of stdout or stderr is not a TTY.
if not gdb and (not sys.stdout.isatty() or not sys.stderr.isatty()):
    Colors.disable_colors()


@contextmanager
def no_colors():
    """
    Context manager to disable colors for a given scope.
    """
    old_val, Colors._enabled = Colors._enabled, False
    yield
    Colors._enabled = old_val


def col(msg, color):
    """
    Utility function that return a string colored with the proper escape
    sequences, for VT100 compatible terminals.

    :param str msg: The message to print.
    :param color: An escape sequence corresponding to the proper color. Pick
        one in the Colors class.
    :rtype: str
    """
    if Colors._enabled:
        return "{0}{1}{2}".format(color, msg, Colors.ENDC)
    else:
        return msg


def printcol(msg, color):
    """
    Utility print function that will print `msg` in color `color`.
    :param str msg: The message to print.
    :param str color: The color escape sequence from the enum class
        Colors which represents the color to use.
    :return: The color-escaped string, resetting the color to blank at the end.
    :rtype: str
    """
    print(col(msg, color))

    # Colored messages are used to show the user how the compilation process is
    # going, so flushing on a regular basis matters. When \n-based flushing is
    # disabled (because of a pipe, for instance), force flushing here.
    sys.stdout.flush()
