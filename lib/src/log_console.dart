part of logger_flutter;

class _WrappedOutput implements LogOutput {
  final Function(OutputEvent e) outputListener;
  final LogOutput innerLogOutput;

  _WrappedOutput(this.outputListener, this.innerLogOutput);

  @override
  void output(OutputEvent event) {
    innerLogOutput.output(event);
    outputListener(event);
  }

  @override
  void destroy() {
    innerLogOutput.destroy();
  }

  @override
  void init() {
    innerLogOutput.init();
  }
}

class LogConsole extends StatefulWidget {
  final bool dark;
  final bool showCloseButton;
  final Map<Level, Color> colorMap;

  static ListQueue<OutputEvent> _outputEventBuffer = ListQueue();
  static bool _initialized = false;
  static final _newLogs = ChangeNotifier();

  LogConsole({this.dark = false, this.showCloseButton = false})
      : assert(_initialized, 'Please call LogConsole.init() first.'),
        colorMap = {
          Level.verbose: Colors.grey,
          Level.debug: dark ? Colors.white : Colors.black,
          Level.info: Colors.lightBlue,
          Level.warning: Colors.orange,
          Level.error: Colors.red,
          Level.wtf: Color(0xFFFF1493),
        };

  /// Attach this LogOutput to your logger instance:
  /// `
  /// Logger(
  ///     printer: PrettyPrinter(
  ///       printTime: true,
  ///       printEmojis: true,
  ///       colors: true,
  ///       methodCount: methodCount,
  ///       errorMethodCount: errMethodCount,
  ///     ),
  ///     level: level,
  ///     output: LogConsole.wrap(output),
  ///     filter: ProductionFiler(),
  ///   );
  /// `
  static LogOutput wrap({int bufferSize = 1000, LogOutput? innerOutput}) {
    _initialized = true;

    final output = innerOutput ?? ConsoleOutput();

    return _WrappedOutput((e) {
      if (_outputEventBuffer.length == bufferSize) {
        _outputEventBuffer.removeFirst();
      }
      _outputEventBuffer.add(e);
      // ignore: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
      _newLogs.notifyListeners();
    }, output);
  }

  @override
  _LogConsoleState createState() => _LogConsoleState();

  static void openLogConsole(BuildContext context) async {
    var logConsole = LogConsole(
      showCloseButton: true,
      dark: Theme.of(context).brightness == Brightness.dark,
    );
    PageRoute route;
    route = MaterialPageRoute(builder: (_) => logConsole);

    await Navigator.push(context, route);
  }
}

class RenderedEvent {
  final int id;
  final Level level;
  final String text;

  RenderedEvent(this.id, this.level, this.text);
}

class _LogConsoleState extends State<LogConsole> {
  final ListQueue<RenderedEvent> _renderedBuffer = ListQueue();
  List<RenderedEvent> _filteredBuffer = [];

  final _scrollController = ScrollController();
  final _filterController = TextEditingController();

  Level _filterLevel = Level.verbose;
  double _logFontSize = 14;

  var _currentId = 0;
  bool _scrollListenerEnabled = true;
  bool _followBottom = true;

  @override
  void initState() {
    super.initState();

    _scrollController.addListener(() {
      if (!_scrollListenerEnabled) return;
      var scrolledToBottom = _scrollController.offset >=
          _scrollController.position.maxScrollExtent;
      if (scrolledToBottom != _followBottom) {
        setState(() {
          _followBottom = scrolledToBottom;
        });
      }
    });

    LogConsole._newLogs.addListener(_onNewLogs);
  }

  void _onNewLogs() {
    setState(() {
      _reloadContent();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    _reloadContent();
  }

  void _reloadContent() {
    _renderedBuffer.clear();
    for (var event in LogConsole._outputEventBuffer) {
      _renderedBuffer.add(_renderEvent(event));
    }
    _refreshFilter();
  }

  void _refreshFilter() {
    var newFilteredBuffer = _renderedBuffer.where((it) {
      var logLevelMatches = it.level.index >= _filterLevel.index;
      if (!logLevelMatches) {
        return false;
      } else if (_filterController.text.isNotEmpty) {
        var filterText = _filterController.text.toLowerCase();
        return it.text.toLowerCase().contains(filterText);
      } else {
        return true;
      }
    }).toList();
    setState(() {
      _filteredBuffer = newFilteredBuffer;
    });

    if (_followBottom) {
      Future.delayed(Duration.zero, _scrollToBottom);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: widget.dark
          ? ThemeData(
        brightness: Brightness.dark,
        accentColor: Colors.blueGrey,
      )
          : ThemeData(
        brightness: Brightness.light,
        accentColor: Colors.lightBlueAccent,
      ),
      home: Scaffold(
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _buildTopBar(),
              Expanded(
                child: _buildLogContent(),
              ),
              _buildBottomBar(),
            ],
          ),
        ),
        floatingActionButton: AnimatedOpacity(
          opacity: _followBottom ? 0 : 1,
          duration: Duration(milliseconds: 150),
          child: Padding(
            padding: EdgeInsets.only(bottom: 60),
            child: FloatingActionButton(
              mini: true,
              clipBehavior: Clip.antiAlias,
              child: Icon(
                Icons.arrow_downward,
                color: widget.dark ? Colors.white : Colors.lightBlue[900],
              ),
              onPressed: _scrollToBottom,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogContent() {

    return Container(
      color: widget.dark ? Colors.black : Colors.grey[150],
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: 1600,
          child: ListView.builder(
            controller: _scrollController,
            itemCount: _filteredBuffer.length,
            itemBuilder: (_, index) {
              RenderedEvent event = _filteredBuffer[index];
              return SelectableText(
                event.text,
                style: TextStyle(
                  color: widget.colorMap[event.level],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return LogBar(
      dark: widget.dark,
      child: Row(
        mainAxisSize: MainAxisSize.max,
        children: <Widget>[
          Text(
            'Log Console',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          Spacer(),
          IconButton(
            icon: Icon(Icons.add),
            onPressed: () {
              setState(() {
                _logFontSize++;
              });
            },
          ),
          IconButton(
            icon: Icon(Icons.remove),
            onPressed: () {
              setState(() {
                _logFontSize--;
              });
            },
          ),
          if (widget.showCloseButton)
            IconButton(
              icon: Icon(Icons.close),
              onPressed: () {
                Navigator.pop(context);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    return LogBar(
      dark: widget.dark,
      child: Row(
        mainAxisSize: MainAxisSize.max,
        children: <Widget>[
          Expanded(
            child: TextField(
              style: TextStyle(fontSize: 20),
              controller: _filterController,
              onChanged: (s) => _refreshFilter(),
              decoration: InputDecoration(
                labelText: 'Filter log output',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          SizedBox(width: 20),
          DropdownButton(
            value: _filterLevel,
            items: [
              DropdownMenuItem(
                child: Text('VERBOSE'),
                value: Level.verbose,
              ),
              DropdownMenuItem(
                child: Text('DEBUG'),
                value: Level.debug,
              ),
              DropdownMenuItem(
                child: Text('INFO'),
                value: Level.info,
              ),
              DropdownMenuItem(
                child: Text('WARNING'),
                value: Level.warning,
              ),
              DropdownMenuItem(
                child: Text('ERROR'),
                value: Level.error,
              ),
              DropdownMenuItem(
                child: Text('WTF'),
                value: Level.wtf,
              )
            ],
            onChanged: (value) {
              _filterLevel = value as Level;
              _refreshFilter();
            },
          )
        ],
      ),
    );
  }

  void _scrollToBottom() async {
    _scrollListenerEnabled = false;

    setState(() {
      _followBottom = true;
    });

    var scrollPosition = _scrollController.position;
    await _scrollController.animateTo(
      scrollPosition.maxScrollExtent,
      duration: Duration(milliseconds: 400),
      curve: Curves.easeOut,
    );

    _scrollListenerEnabled = true;
  }

  RenderedEvent _renderEvent(OutputEvent event) {
    var text = '';
    RegExp regExp = RegExp(r'(\[38;5;199m|\[38;5;196m|\[38;5;208m|\[38;5;12m|\[38;5;244m|\[48;5;196m|\[48;5;199m|\p{S}.\[0m|\[0m|\[39m|\[49m)', unicode: true);
    event.lines.forEach((element) {
      text = text + element.replaceAll(regExp, '').trim() + '\n';
    });
    return RenderedEvent(
      _currentId++,
      event.level,
      text,
    );
  }

  @override
  void dispose() {
    LogConsole._newLogs.removeListener(_onNewLogs);
    super.dispose();
  }
}

class LogBar extends StatelessWidget {
  final bool dark;
  final Widget child;

  LogBar({this.dark = false, required this.child});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 60,
      child: Container(
        decoration: BoxDecoration(
          boxShadow: [
            if (!dark)
              BoxShadow(
                color: Colors.grey[400]!,
                blurRadius: 3,
              ),
          ],
        ),
        child: Material(
          color: dark ? Colors.blueGrey[900] : Colors.white,
          child: Padding(
            padding: EdgeInsets.fromLTRB(15, 8, 15, 8),
            child: child,
          ),
        ),
      ),
    );
  }
}
