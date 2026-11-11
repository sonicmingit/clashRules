using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Text;
using System.Text.RegularExpressions;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using System.Xml.Serialization;
using Microsoft.Win32;

public sealed class Settings {
    public string Engine = "", Bind = "127.0.0.1", Port = "1080", Exit = "", List = "127.0.0.1", User = "";
    public int Mode = 1;
    public bool Authenticate;
}

public sealed class Manager : Window {
    readonly string directory = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Socks5Manager");
    readonly string settingsPath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "settings.xml");
    readonly StackPanel fields = new StackPanel();
    readonly StackPanel toolbar = new StackPanel();
    readonly TextBlock status = new TextBlock { Margin = new Thickness(0,8,0,8) };
    readonly TextBox clientAddresses = new TextBox { IsReadOnly = true, Visibility = Visibility.Collapsed,
        MaxHeight = 72, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, TextWrapping = TextWrapping.Wrap,
        Margin = new Thickness(0,0,0,8), Padding = new Thickness(6) };
    readonly ListBox logs = new ListBox();
    readonly ListView clients = new ListView();
    readonly TextBlock clientSummary = new TextBlock();
    readonly TextBox engine, bind, port, exit, list, user;
    readonly PasswordBox password = new PasswordBox();
    readonly ComboBox mode = new ComboBox { ItemsSource = new[] { "全部允许", "白名单", "黑名单" } };
    readonly CheckBox authentication = new CheckBox { Content = "启用用户名和密码" };
    readonly System.Windows.Forms.NotifyIcon tray;
    readonly System.Drawing.Icon appIcon;
    Process proxy;
    string activeConfig, endpoint;
    bool reportedReady, quitting;
    DateTime started;
    int activePort;
    string activeBind;

    [DllImport("iphlpapi.dll")]
    static extern uint GetExtendedTcpTable(IntPtr table, ref int size, bool sort, int family, int tableClass, uint reserved);

    static Dictionary<string,int> ReadConnections(int processId, int localPort, out bool listening) {
        listening = false;
        var clients = new Dictionary<string,int>();
        int networkPort = (ushort)IPAddress.HostToNetworkOrder(unchecked((short)localPort));
        ReadTcpTable(2, processId, networkPort, clients, ref listening);
        ReadTcpTable(23, processId, networkPort, clients, ref listening);
        return clients;
    }

    static void ReadTcpTable(int family, int processId, int networkPort,
        Dictionary<string,int> clients, ref bool listening) {
        bool ipv6 = family == 23;
        int stride = ipv6 ? 56 : 24;
        int size = 0;
        uint result = GetExtendedTcpTable(IntPtr.Zero, ref size, false, family, 5, 0);
        if (ipv6 && result == 50) return;
        if (size < 4) throw new InvalidOperationException("无法读取 TCP 状态。");
        IntPtr table = Marshal.AllocHGlobal(size);
        try {
            if (GetExtendedTcpTable(table, ref size, false, family, 5, 0) != 0)
                throw new InvalidOperationException("TCP 状态暂不可用。");
            int rows = Marshal.ReadInt32(table);
            for (int i = 0; i < rows && i < (size - 4) / stride; i++) {
                int offset = 4 + i * stride;
                if (Marshal.ReadInt32(table, offset + (ipv6 ? 52 : 20)) != processId ||
                    (Marshal.ReadInt32(table, offset + (ipv6 ? 20 : 8)) & 65535) != networkPort) continue;
                int state = Marshal.ReadInt32(table, offset + (ipv6 ? 48 : 0));
                if (state == 2) listening = true;
                if (state != 5) continue;
                var address = new byte[ipv6 ? 16 : 4];
                Marshal.Copy(IntPtr.Add(table, offset + (ipv6 ? 24 : 12)), address, 0, address.Length);
                var ip = new IPAddress(address);
                string source = (ip.IsIPv4MappedToIPv6 ? ip.MapToIPv4() : ip).ToString();
                int count;
                clients.TryGetValue(source, out count);
                clients[source] = count + 1;
            }
        } finally { Marshal.FreeHGlobal(table); }
    }

    public sealed class ClientRow {
        public string Address { get; set; }
        public int Connections { get; set; }
    }

    void ShowClients(Dictionary<string,int> snapshot) {
        var rows = snapshot.OrderBy(pair => pair.Key)
            .Select(pair => new ClientRow { Address = pair.Key, Connections = pair.Value }).ToArray();
        clients.ItemsSource = rows;
        clientSummary.Text = rows.Length + " 个来源 IP · " + rows.Sum(row => row.Connections) + " 条 TCP 连接";
    }

    [STAThread] public static void Main() {
        bool first;
        using (var mutex = new System.Threading.Mutex(true, @"Local\Socks5Manager", out first)) {
            if (!first) { MessageBox.Show("管理器已运行，请从系统托盘打开。"); return; }
            new Application().Run(new Manager());
        }
    }

    Manager() {
        Title = "SOCKS5 代理管理器";
        Width = 1060; Height = 740; MinWidth = 760; MinHeight = 490;
        FontFamily = new System.Windows.Media.FontFamily("Microsoft YaHei UI");
        FontSize = 14;
        Background = Paint("#EEF3F8");
        Foreground = Paint("#172B46");
        appIcon = System.Drawing.Icon.ExtractAssociatedIcon(System.Reflection.Assembly.GetExecutingAssembly().Location);
        if (appIcon != null)
            Icon = Imaging.CreateBitmapSourceFromHIcon(appIcon.Handle, Int32Rect.Empty, BitmapSizeOptions.FromEmptyOptions());
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        Directory.CreateDirectory(directory);
        var saved = new Settings();
        try {
            string previousPath = Path.Combine(directory, "settings.xml");
            bool usePrevious = !File.Exists(settingsPath) && File.Exists(previousPath);
            using (var stream = File.OpenRead(usePrevious ? previousPath : settingsPath))
                saved = (Settings)new XmlSerializer(typeof(Settings)).Deserialize(stream);
            if (usePrevious) {
                try { Save(saved); }
                catch (Exception error) { Append("无法迁移设置：" + error.Message); }
            }
        } catch (FileNotFoundException) { }
        catch (Exception e) { Append("读取设置失败：" + e.Message); }

        var layout = new DockPanel { Margin = new Thickness(20) };
        var header = Card(toolbar);
        header.Background = Paint("#142A46");
        header.Margin = new Thickness(0,0,0,14);
        DockPanel.SetDock(header, Dock.Top);
        layout.Children.Add(header);
        var body = new Grid();
        body.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(350) });
        body.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(14) });
        body.ColumnDefinitions.Add(new ColumnDefinition());
        layout.Children.Add(body);
        var scroll = new ScrollViewer { Content = fields, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
        body.Children.Add(Card(scroll));
        var logPanel = new DockPanel();
        var logCard = Card(logPanel);
        Grid.SetColumn(logCard, 2);
        body.Children.Add(logCard);
        Content = layout;
        var brand = new StackPanel { Orientation = Orientation.Horizontal };
        toolbar.Children.Add(brand);
        brand.Children.Add(new Image { Source = Icon, Width = 28, Height = 28, Margin = new Thickness(0,0,10,0) });
        brand.Children.Add(new TextBlock { Text = Title, FontSize = 23, FontWeight = FontWeights.SemiBold, Foreground = Brushes.White });
        status.Foreground = Paint("#B9E4FF");
        toolbar.Children.Add(status);
        toolbar.Children.Add(clientAddresses);
        fields.Children.Add(Heading("网络"));
        bind = Input("监听 IPv4", saved.Bind);
        fields.Children.Add(new TextBlock { Text = "客户端连接此 IP。0.0.0.0 表示监听所有网卡。",
            FontSize = 12, Foreground = Paint("#53677D"), Margin = new Thickness(0,5,0,0), TextWrapping = TextWrapping.Wrap });
        var endpointFields = new Grid();
        endpointFields.ColumnDefinitions.Add(new ColumnDefinition());
        endpointFields.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(94) });
        fields.Children.Add(endpointFields);
        var exitField = new StackPanel { Margin = new Thickness(0,0,10,0) };
        var portField = new StackPanel();
        Grid.SetColumn(portField, 1);
        endpointFields.Children.Add(exitField);
        endpointFields.Children.Add(portField);
        exit = new TextBox { Text = saved.Exit };
        port = new TextBox { Text = saved.Port };
        AddField(exitField, "出口 IPv4", exit);
        AddField(portField, "监听端口", port);
        exit.ToolTip = "留空使用 Windows 路由";
        fields.Children.Add(new TextBlock { Text = "出口留空使用 Windows 路由。客户端填写监听端口。",
            FontSize = 12, Foreground = Paint("#53677D"), Margin = new Thickness(0,5,0,0), TextWrapping = TextWrapping.Wrap });
        var accessHeading = Heading("访问控制");
        accessHeading.Margin = new Thickness(0,16,0,2);
        fields.Children.Add(accessHeading);
        Add("访问模式", mode); mode.SelectedIndex = saved.Mode;
        list = Input("来源 IPv4 / CIDR / 起止范围（换行或逗号分隔）", saved.List);
        list.AcceptsReturn = true; list.Height = 56; list.VerticalScrollBarVisibility = ScrollBarVisibility.Auto;
        mode.SelectionChanged += delegate { list.IsEnabled = mode.SelectedIndex != 0; };
        list.IsEnabled = mode.SelectedIndex != 0;
        fields.Children.Add(authentication); authentication.IsChecked = saved.Authenticate;
        user = Input("用户名", saved.User);
        Add("密码（每次打开软件后输入）", password);
        Action refreshAuthentication = delegate { user.IsEnabled = password.IsEnabled = authentication.IsChecked == true; };
        authentication.Checked += delegate { refreshAuthentication(); };
        authentication.Unchecked += delegate { refreshAuthentication(); };
        refreshAuthentication();
        var advanced = new Expander { Header = "3proxy 内核", Margin = new Thickness(0,14,0,0) };
        var enginePanel = new StackPanel();
        advanced.Content = enginePanel;
        fields.Children.Add(advanced);
        engine = new TextBox { Text = File.Exists(saved.Engine) ? saved.Engine : "", MinHeight = 28,
            ToolTip = "留空使用程序旁 bin 目录内的 3proxy.exe" };
        enginePanel.Children.Add(engine);
        var engineButtons = new WrapPanel();
        enginePanel.Children.Add(engineButtons);
        Button(engineButtons,"选择文件", delegate {
            var dialog = new OpenFileDialog { Filter = "3proxy.exe|3proxy.exe", CheckFileExists = true };
            if (dialog.ShowDialog(this) == true) engine.Text = dialog.FileName;
        });
        Button(engineButtons,"使用内置", delegate { engine.Clear(); });
        var buttons = new WrapPanel { Margin = new Thickness(0,8,0,0) };
        toolbar.Children.Add(buttons);
        var startButton = Button(buttons,"启动代理", delegate { RunSafe(delegate { if (proxy == null) Start(ReadSettings()); }); });
        startButton.Background = Paint("#167AC6");
        startButton.Foreground = Brushes.White;
        Button(buttons,"停止", delegate { RunSafe(Stop); });
        Button(buttons,"应用设置", delegate { RunSafe(ApplySettings); });
        var logHeader = new DockPanel { Margin = new Thickness(0,0,0,8) };
        var logActions = new StackPanel();
        DockPanel.SetDock(logActions, Dock.Right);
        logHeader.Children.Add(logActions);
        Button(logActions,"清空日志", delegate { logs.Items.Clear(); });
        logHeader.Children.Add(Heading("连接日志"));
        DockPanel.SetDock(logHeader, Dock.Top);
        logPanel.Children.Add(logHeader);
        var hint = new TextBlock { Text = "会话结束或请求被拒绝时写入", Foreground = Paint("#53677D"), Margin = new Thickness(0,0,0,10) };
        DockPanel.SetDock(hint, Dock.Top);
        logPanel.Children.Add(hint);
        logs.Background = Paint("#F4F7FB");
        logs.BorderBrush = Paint("#D7E1EE");
        logs.FontFamily = new FontFamily("Consolas");
        logs.FontSize = 12;
        logPanel.Children.Add(logs);
        var livePanel = new DockPanel { Margin = new Thickness(10) };
        clientSummary.Margin = new Thickness(0,0,0,8);
        DockPanel.SetDock(clientSummary, Dock.Top);
        livePanel.Children.Add(clientSummary);
        var columns = new GridView();
        columns.Columns.Add(new GridViewColumn { Header = "来源 IP", Width = 180, DisplayMemberBinding = new System.Windows.Data.Binding("Address") });
        columns.Columns.Add(new GridViewColumn { Header = "TCP 连接", Width = 105, DisplayMemberBinding = new System.Windows.Data.Binding("Connections") });
        clients.View = columns;
        livePanel.Children.Add(clients);
        var tabs = new TabControl();
        tabs.Items.Add(new TabItem { Header = "在线客户端", Content = livePanel });
        tabs.Items.Add(new TabItem { Header = "连接日志", Content = logPanel });
        var help = new StackPanel { Margin = new Thickness(14) };
        help.Children.Add(Heading("连接 SOCKS5 代理"));
        help.Children.Add(new TextBlock {
            Text = "1. 点击「启动代理」。\n\n2. 在第三方客户端选择 SOCKS5，填写顶部显示的 IP 和端口。局域网设备应选择与它同网段的 IP。\n\n3. 已启用认证时，填写设置中的用户名和密码。",
            TextWrapping = TextWrapping.Wrap, LineHeight = 22
        });
        tabs.Items.Add(new TabItem { Header = "使用说明", Content = new ScrollViewer { Content = help, VerticalScrollBarVisibility = ScrollBarVisibility.Auto } });
        logCard.Child = tabs;
        ShowClients(new Dictionary<string,int>());
        tray = new System.Windows.Forms.NotifyIcon { Icon = appIcon ?? System.Drawing.SystemIcons.Shield, Text = Title, Visible = true };
        tray.DoubleClick += delegate { Restore(); };
        var menu = new System.Windows.Forms.ContextMenuStrip();
        menu.Items.Add("打开", null, delegate { Restore(); });
        menu.Items.Add("启动代理", null, delegate { RunSafe(delegate { if (proxy == null) Start(ReadSettings()); }); });
        menu.Items.Add("停止代理", null, delegate { RunSafe(Stop); });
        menu.Items.Add("退出", null, delegate { quitting = true; Close(); });
        tray.ContextMenuStrip = menu;
        StateChanged += delegate { if (WindowState == WindowState.Minimized) Hide(); };
        Closing += delegate(object sender, System.ComponentModel.CancelEventArgs e) {
            if (!quitting) { e.Cancel = true; Hide(); return; }
            try { Stop(); } catch (Exception error) { e.Cancel = true; quitting = false; MessageBox.Show(error.Message); }
            if (!e.Cancel) { tray.Dispose(); if (appIcon != null) appIcon.Dispose(); }
        };
        var timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(500) };
        timer.Tick += delegate { RefreshStatus(); };
        timer.Start();
        status.Text = "● 已停止";
    }

    void Restore() { Show(); WindowState = WindowState.Normal; Activate(); }
    static Brush Paint(string color) { return (Brush)new BrushConverter().ConvertFromString(color); }
    static Border Card(UIElement content) {
        return new Border { Background = Brushes.White, BorderBrush = Paint("#D7E1EE"),
            BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(12),
            Padding = new Thickness(16), Child = content };
    }
    static TextBlock Heading(string title) {
        return new TextBlock { Text = title, FontSize = 18, FontWeight = FontWeights.SemiBold,
            Margin = new Thickness(0,0,0,6), VerticalAlignment = VerticalAlignment.Center };
    }
    void Add(string label, Control control) {
        AddField(fields, label, control);
    }
    static void AddField(Panel panel, string label, Control control) {
        panel.Children.Add(new TextBlock { Text = label, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0,8,0,4) });
        control.MinHeight = 28;
        panel.Children.Add(control);
    }
    TextBox Input(string label, string value) {
        var input = new TextBox { Text = value };
        Add(label, input);
        return input;
    }
    static Button Button(Panel panel, string name, Action action) {
        var button = new Button { Content = name, Padding = new Thickness(12,3,12,3), Margin = new Thickness(0,3,8,3) };
        button.Click += delegate { action(); };
        panel.Children.Add(button);
        return button;
    }
    void RunSafe(Action action) {
        try { action(); } catch (Exception error) { MessageBox.Show(this, error.Message, Title); }
    }
    void Append(string line) {
        if (logs.Items.Count >= 1500) logs.Items.RemoveAt(0);
        logs.Items.Add(line);
        logs.ScrollIntoView(line);
    }
    Settings ReadSettings() {
        return new Settings { Engine = engine.Text.Trim(), Bind = bind.Text.Trim(), Port = port.Text.Trim(),
            Exit = exit.Text.Trim(), List = list.Text, Mode = mode.SelectedIndex, User = user.Text,
            Authenticate = authentication.IsChecked == true };
    }
    static string IPv4(string value) {
        IPAddress address;
        if (!IPAddress.TryParse(value, out address) || address.AddressFamily != AddressFamily.InterNetwork || address.ToString() != value)
            throw new ArgumentException("IPv4 地址无效：" + value);
        return value;
    }
    static uint Number(string value) {
        return IPAddress.Parse(IPv4(value)).GetAddressBytes().Aggregate(0u, (n,b) => (n << 8) | b);
    }
    static string Range(string value) {
        var cidr = value.Split('/');
        if (cidr.Length == 2) {
            int length;
            if (!int.TryParse(cidr[1], out length) || length < 0 || length > 32) throw new ArgumentException("CIDR 无效：" + value);
            return IPv4(cidr[0]) + "/" + length;
        }
        var pair = value.Split('-');
        if (pair.Length == 2) {
            var low = pair[0].Trim(); var high = pair[1].Trim();
            if (Number(low) > Number(high)) throw new ArgumentException("IP 范围顺序无效：" + value);
            return low + "-" + high;
        }
        return IPv4(value);
    }
    public static string Config(Settings settings, string secret) {
        int number;
        if (!int.TryParse(settings.Port, out number) || number < 1 || number > 65535)
            throw new ArgumentException("端口必须在 1 到 65535 之间。");
        var output = new StringBuilder();
        output.AppendLine("log");
        output.AppendLine("logformat \"L%Y-%m-%d %H:%M:%S | %C:%c | %R:%r | %E | %T\"");
        if (settings.Authenticate) {
            const string pattern = @"\A[A-Za-z0-9_.@!+-]{1,64}\z";
            if (!Regex.IsMatch(settings.User, pattern) || !Regex.IsMatch(secret, pattern))
                throw new ArgumentException("账号和密码须为 1–64 位字母、数字或 _.@!+-");
            output.AppendLine("users " + settings.User + ":CL:" + secret);
        }
        output.AppendLine(settings.Authenticate ? "auth strong" : "auth iponly");
        if (settings.Mode < 0 || settings.Mode > 2) throw new ArgumentException("请选择访问模式。");
        if (settings.Mode != 0) {
            var ranges = settings.List.Split(new[] { ',', '，', '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries)
                .Select(value => value.Trim()).Where(value => value.Length != 0).Select(Range).Distinct().ToArray();
            if (ranges.Length == 0) throw new ArgumentException("请至少输入一个来源 IP 或网段。");
            output.AppendLine((settings.Mode == 1 ? "allow" : "deny") + " * " + string.Join(",", ranges));
        }
        output.AppendLine(settings.Mode == 1 ? "deny *" : "allow *");
        output.AppendLine("socks -p" + number + " -i" + IPv4(settings.Bind) +
            (settings.Exit.Length == 0 ? "" : " -e" + IPv4(settings.Exit)));
        return output.ToString();
    }
    void Save(Settings settings) {
        string path = settingsPath;
        string temporary = path + ".tmp";
        using (var stream = File.Create(temporary)) new XmlSerializer(typeof(Settings)).Serialize(stream, settings);
        if (File.Exists(path)) File.Replace(temporary, path, null);
        else File.Move(temporary, path);
    }
    void ApplySettings() {
        var settings = ReadSettings();
        Config(settings, password.Password);
        if (proxy == null) { Save(settings); Append("设置已保存。"); return; }
        ResolveEngine(settings);
        Stop();
        Start(settings);
    }
    string ResolveEngine(Settings settings) {
        if (settings.Engine.Length == 0) {
            using (var resource = typeof(Manager).Assembly.GetManifestResourceStream("Embedded.3proxy.exe")) {
                if (resource != null) return ExtractEngine(resource);
            }
        }
        string executable = settings.Engine.Length == 0 ? Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "bin", "3proxy.exe") : settings.Engine;
        if (!File.Exists(executable)) throw new FileNotFoundException("请选择可用的 3proxy.exe。");
        return Path.GetFullPath(executable);
    }
    string ExtractEngine(Stream resource) {
        using (var sha = System.Security.Cryptography.SHA256.Create()) {
            byte[] expected = sha.ComputeHash(resource);
            string version = BitConverter.ToString(expected).Replace("-", "");
            string folder = Path.Combine(directory, "engine", version);
            Directory.CreateDirectory(folder);
            string executable = Path.Combine(folder, "3proxy.exe");
            if (File.Exists(executable)) {
                using (var current = File.OpenRead(executable)) {
                    if (sha.ComputeHash(current).SequenceEqual(expected)) return executable;
                }
                throw new IOException("内置内核缓存校验失败：" + executable);
            }
            string temporary = executable + "." + Guid.NewGuid().ToString("N") + ".tmp";
            try {
                resource.Position = 0;
                using (var output = File.Create(temporary)) resource.CopyTo(output);
                File.Move(temporary, executable);
                return executable;
            } finally {
                if (File.Exists(temporary)) File.Delete(temporary);
            }
        }
    }
    void Start(Settings settings) {
        string config = Config(settings, password.Password);
        string executable = ResolveEngine(settings);
        Save(settings);
        string fileName = "proxy-" + Guid.NewGuid().ToString("N") + ".cfg";
        activeConfig = Path.Combine(directory, fileName);
        activePort = int.Parse(settings.Port);
        activeBind = settings.Bind;
        endpoint = activeBind + ":" + activePort;
        reportedReady = false;
        try {
            File.WriteAllText(activeConfig, config, Encoding.ASCII);
            var child = new Process { StartInfo = new ProcessStartInfo(executable, fileName) {
                WorkingDirectory = directory, UseShellExecute = false, CreateNoWindow = true,
                RedirectStandardOutput = true, RedirectStandardError = true
            } };
            DataReceivedEventHandler capture = delegate(object sender, DataReceivedEventArgs args) {
                if (args.Data != null) Dispatcher.BeginInvoke(new Action(delegate {
                    if (proxy != child) return;
                    Append(args.Data);
                    if (args.Data.IndexOf(" | Accepting connections [", StringComparison.Ordinal) >= 0)
                        reportedReady = true;
                }));
            };
            child.OutputDataReceived += capture;
            child.ErrorDataReceived += capture;
            if (!child.Start()) { child.Dispose(); throw new InvalidOperationException("无法启动代理内核。"); }
            proxy = child;
            child.BeginOutputReadLine(); child.BeginErrorReadLine();
            started = DateTime.UtcNow;
            status.Text = "正在启动 · " + endpoint;
        } catch { Stop(); throw; }
    }
    void Stop() {
        if (proxy != null) {
            if (!proxy.HasExited) {
                proxy.Kill();
                if (!proxy.WaitForExit(3000)) throw new InvalidOperationException("代理进程未能停止。");
            }
            proxy.Dispose();
            proxy = null;
        }
        if (activeConfig != null) { File.Delete(activeConfig); activeConfig = null; }
        ShowClients(new Dictionary<string,int>());
        clientAddresses.Visibility = Visibility.Collapsed;
        clientAddresses.Clear();
        status.Text = "● 已停止";
    }
    static string FormatClientAddresses(string address, int port) {
        if (address != "0.0.0.0") {
            string scope = IPAddress.IsLoopback(IPAddress.Parse(address)) ? "（仅本机）" : "";
            return "SOCKS5 地址" + scope + "  socks5://" + address + ":" + port;
        }
        var lan = NetworkInterface.GetAllNetworkInterfaces()
            .Where(adapter => adapter.OperationalStatus == OperationalStatus.Up)
            .SelectMany(adapter => adapter.GetIPProperties().UnicastAddresses)
            .Select(item => item.Address)
            .Where(ip => ip.AddressFamily == AddressFamily.InterNetwork && !IPAddress.IsLoopback(ip))
            .Select(ip => "socks5://" + ip + ":" + port).Distinct().OrderBy(uri => uri).ToArray();
        string local = "本机  socks5://127.0.0.1:" + port;
        return lan.Length == 0 ? local : "局域网  " + string.Join("    ", lan) + Environment.NewLine + local;
    }
    void RefreshStatus() {
        if (proxy == null) return;
        try {
            if (proxy.HasExited) {
                int code = proxy.ExitCode;
                Stop();
                status.Text = "● 内核已退出 · " + code;
                return;
            }
            var age = DateTime.UtcNow - started;
            bool listening;
            var snapshot = ReadConnections(proxy.Id, activePort, out listening);
            ShowClients(snapshot);
            if (listening || reportedReady) {
                status.Text = "● 运行中 · " + endpoint + " · " + age.ToString(@"hh\:mm\:ss")
                    + " · 当前 TCP 连接 " + snapshot.Values.Sum();
                if (clientAddresses.Visibility != Visibility.Visible) {
                    clientAddresses.Text = FormatClientAddresses(activeBind, activePort);
                    clientAddresses.Visibility = Visibility.Visible;
                }
            } else if (age.TotalSeconds >= 5) status.Text = "● 内核运行中 · 尚未确认监听，请查看日志";
        } catch (Exception error) { status.Text = error.Message; }
    }
}
