# App-owned S6 cell helpers; the interpreter and wheels are unmodified upstream bytes.
import base64 as _memoshi_base64
import io as _memoshi_io
import json as _memoshi_json

_memoshi_tables = []
_memoshi_figures = []
_memoshi_output_bytes = 0


def memoshi_table(frame, limit=100):
    """Return up to 100 rows as native table data, never HTML or executable output."""
    global _memoshi_output_bytes
    if len(_memoshi_tables) >= 8 or not isinstance(limit, int) or not 0 <= limit <= 100:
        raise ValueError("memoshi_output_limit")
    rows = frame.head(limit).to_json(orient="values", date_format="iso")
    columns = [str(column) for column in frame.columns]
    size = len(rows.encode("utf-8")) + sum(len(column.encode("utf-8")) for column in columns)
    _memoshi_output_bytes += size
    if _memoshi_output_bytes > 8 * 1024 * 1024:
        raise ValueError("memoshi_output_limit")
    _memoshi_tables.append({"columns": columns, "jsonRows": rows, "totalRows": len(frame)})


def memoshi_figure(figure=None):
    """Capture a real Agg-rendered Matplotlib figure as a bounded PNG, not a screenshot."""
    global _memoshi_output_bytes
    import matplotlib.pyplot as pyplot
    if len(_memoshi_figures) >= 8:
        raise ValueError("memoshi_output_limit")
    if figure is None:
        figure = pyplot.gcf()
    buffer = _memoshi_io.BytesIO()
    figure.savefig(buffer, format="png", dpi=100)
    png = buffer.getvalue()
    _memoshi_output_bytes += len(png)
    if len(png) > 8 * 1024 * 1024 or _memoshi_output_bytes > 32 * 1024 * 1024:
        raise ValueError("memoshi_output_limit")
    _memoshi_figures.append({"png": _memoshi_base64.b64encode(png).decode("ascii")})
    pyplot.close(figure)


def _memoshi_results():
    return _memoshi_json.dumps({"tables": _memoshi_tables, "figures": _memoshi_figures}, allow_nan=False)
