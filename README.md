# nu-demo-v

这是一个用 V 语言实现的 Nushell 插件示例，协议行为参考了官方的 Node.js 版本。

插件导出的命令名是 `v_example`，它会返回一张示例表格，方便你检查 Nushell 插件协议和输出格式。

## 前置条件

- 安装 V 编译器
- 安装 Nushell

插件会在启动时读取当前机器上的 `nu --version`，所以本地 Nu 版本需要可执行且能返回版本号。

## 构建

```bash
v -o nu_plugin_v_example nu_plugin_v_example.v
```

构建完成后会得到一个可执行文件 `nu_plugin_v_example`。

## 在 Nushell 中注册

在项目目录下执行：

```nushell
plugin add ./nu_plugin_v_example
plugin use ./nu_plugin_v_example
```

如果你想反复调试，也可以直接把生成的可执行文件放进 `$env.PATH`，然后在 Nushell 里通过插件名调用它。

## 使用方法

```nushell
v_example 2 "3"
```

这个命令的两个位置参数会被 Nushell 按插件签名传入，插件会返回一个包含 `Record` 的表格数据。

## 期望输出

大致会看到类似下面的结果：

```nushell
╭───┬───────┬───────┬───────╮
│ # │ one   │ two   │ three │
├───┼───────┼───────┼───────┤
│ 0 │ 0     │ 0     │ 0     │
│ 1 │ 1     │ 2     │ 3     │
│ 2 │ 2     │ 4     │ 6     │
╰───┴───────┴───────┴───────╯
```

## 调试提示

- 如果 `plugin add` 后找不到命令，先确认可执行文件名以 `nu_plugin_` 开头。
- 如果插件直接退出，检查它是否能在当前环境中执行 `nu --version`。
- 如果你修改了源码，重新执行 `v -o nu_plugin_v_example nu_plugin_v_example.v` 再加载插件。
