{BufferedProcess, CompositeDisposable} = require 'atom'
{exists, unlink, writeFile} = require 'fs'
{join, resolve} = require 'path'
{randomBytes} = require 'crypto'
{tmpdir} = require 'os'

findFile = (dir, file, cb) ->
  absolute = join dir, file
  exists absolute, (doesExist) ->
    return cb absolute if doesExist
    parent = resolve dir, '..'
    return cb() if dir is parent
    findFile parent, file, cb

lint = (editor, command, args) ->
  filePath = editor.getPath()
  tmpPath = join tmpdir(), randomBytes(32).toString 'hex'
  out = ''

  appendToOut = (data) -> out += data
  getConfig = (cb) -> findFile filePath, '.scss-lint.yml', cb
  writeTmp = (cb) -> writeFile tmpPath, editor.getText(), cb
  cleanup = (cb) -> unlink tmpPath, cb

  new Promise (resolve, reject) -> getConfig (config) -> writeTmp (er) ->
    return reject er if er
    new BufferedProcess
      command: command
      args: [
        '-f'
        'JSON'
        (if config then ['-c', config] else [])...
        args...
        tmpPath
      ]
      stdout: appendToOut
      stderr: appendToOut
      exit: -> cleanup ->
        try errors = JSON.parse(out)
        return reject new Error out unless errors
        resolve (errors[tmpPath] || []).map (error) ->
          line = (error.line or 1) - 1
          col = (error.column or 1) - 1
          type: error.severity || 'error'
          text: (error.reason or 'Unknown Error') +
            (if error.linter then " (#{error.linter})" else ''),
          filePath: filePath,
          range: [[line, col], [line, col + (error.length or 0)]]

module.exports =
  config:
    executablePath:
      type: 'string'
      title: 'Executable Path'
      default: 'scss-lint'
    additionalArguments:
      title: 'Additional Arguments'
      type: 'string'
      default: ''

  activate: ->
    prefix = 'linter-scss-lint-caseywebdev.'
    @subscriptions = new CompositeDisposable
    @subscriptions.add atom.config.observe "#{prefix}executablePath",
      (executablePath) => @executablePath = executablePath
    @subscriptions.add atom.config.observe "#{prefix}additionalArguments",
      (args) => @additionalArguments = if args then args.split ' ' else []

  deactivate: ->
    @subscriptions.dispose()

  provideLinter: ->
    provider =
      grammarScopes: ['source.css.scss'],
      scope: 'file'
      lintOnFly: true
      lint: (editor) => lint editor, @executablePath, @additionalArguments
