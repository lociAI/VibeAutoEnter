using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Media;
using System.Runtime.CompilerServices;
using System.Text;
using System.Windows.Automation;
using System.Windows.Threading;

namespace VibeAutoEnter;

public sealed class WindowsAutoEnterMonitor : INotifyPropertyChanged
{
    private static readonly HashSet<string> TerminalProcesses = new(StringComparer.OrdinalIgnoreCase)
    {
        "WindowsTerminal", "cmd", "powershell", "pwsh", "mintty", "ConEmu64", "wezterm-gui", "alacritty"
    };

    private static readonly HashSet<string> IdeProcesses = new(StringComparer.OrdinalIgnoreCase)
    {
        "Cursor", "Windsurf", "Code", "Claude"
    };

    private static readonly string[] YesNoPatterns =
    {
        "[y/n]", "(y/n)", "[yes/no]", "(yes/no)", "proceed?", "allow command?",
        "do you want to continue", "continue? [y", "overwrite?"
    };

    private static readonly string[] NumberChoicePatterns =
    {
        "1. yes", "1. accept", "pick a number", "pick an option", "select an option",
        "enter choice", "enter selection", "choose an option", "choice [1]:",
        "selection [1]:", "select [1-", "pick [1-", "choose [1-", "option [1]:"
    };

    private static readonly string[] GuiPromptReadyIndicators =
    {
        "Press Enter to send", "Hit Enter", "Send message", "Ctrl+Enter"
    };

    private readonly DispatcherTimer _scanTimer;
    private readonly DispatcherTimer _swapTimer;
    private readonly Dictionary<string, DateTime> _answeredCooldowns = new();
    private int _swapIndex;

    private bool _isRunning;
    private bool _cliAutoAcceptEnabled = true;
    private bool _cliAutoPickNumberEnabled = true;
    private bool _autoSwapWindows;
    private bool _autoEnterEnabled = true;
    private bool _playSoundOnCompletion = true;
    private double _cliEnterDelay = 0.6;
    private double _enterDelay = 1.0;
    private double _swapInterval = 3.0;
    private int _enterPressCount;

    public ObservableCollection<string> ActivityLog { get; } = new();

    public bool IsRunning
    {
        get => _isRunning;
        set { _isRunning = value; OnPropertyChanged(); OnPropertyChanged(nameof(StatusText)); }
    }

    public string StatusText => IsRunning ? "Monitoring Active" : "Paused";

    public bool CliAutoAcceptEnabled
    {
        get => _cliAutoAcceptEnabled;
        set { _cliAutoAcceptEnabled = value; OnPropertyChanged(); }
    }

    public bool CliAutoPickNumberEnabled
    {
        get => _cliAutoPickNumberEnabled;
        set { _cliAutoPickNumberEnabled = value; OnPropertyChanged(); }
    }

    public bool AutoSwapWindows
    {
        get => _autoSwapWindows;
        set
        {
            _autoSwapWindows = value;
            OnPropertyChanged();
            UpdateSwapTimer();
        }
    }

    public bool AutoEnterEnabled
    {
        get => _autoEnterEnabled;
        set { _autoEnterEnabled = value; OnPropertyChanged(); }
    }

    public bool PlaySoundOnCompletion
    {
        get => _playSoundOnCompletion;
        set { _playSoundOnCompletion = value; OnPropertyChanged(); }
    }

    public double CliEnterDelay
    {
        get => _cliEnterDelay;
        set { _cliEnterDelay = value; OnPropertyChanged(); }
    }

    public double EnterDelay
    {
        get => _enterDelay;
        set { _enterDelay = value; OnPropertyChanged(); }
    }

    public double SwapInterval
    {
        get => _swapInterval;
        set
        {
            _swapInterval = value;
            OnPropertyChanged();
            UpdateSwapTimer();
        }
    }

    public int EnterPressCount
    {
        get => _enterPressCount;
        set { _enterPressCount = value; OnPropertyChanged(); }
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    public WindowsAutoEnterMonitor()
    {
        _scanTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(500) };
        _scanTimer.Tick += (_, _) => ScanWindows();

        _swapTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(_swapInterval) };
        _swapTimer.Tick += (_, _) => CycleTerminalWindows();

        AddActivity("VibeAutoEnter for Windows ready");
    }

    public void ToggleMonitoring()
    {
        IsRunning = !IsRunning;
        if (IsRunning)
        {
            _scanTimer.Start();
            UpdateSwapTimer();
            AddActivity("Started monitoring terminals & IDEs");
        }
        else
        {
            _scanTimer.Stop();
            _swapTimer.Stop();
            AddActivity("Paused monitoring");
        }
    }

    private void UpdateSwapTimer()
    {
        _swapTimer.Stop();
        if (IsRunning && AutoSwapWindows)
        {
            _swapTimer.Interval = TimeSpan.FromSeconds(Math.Max(1.5, SwapInterval));
            _swapTimer.Start();
        }
    }

    private void CycleTerminalWindows()
    {
        if (!IsRunning || !AutoSwapWindows) return;

        var terminals = Win32Helper.GetVisibleWindows()
            .Where(w => TerminalProcesses.Contains(w.ProcessName))
            .ToList();

        if (terminals.Count <= 1) return;

        _swapIndex = (_swapIndex + 1) % terminals.Count;
        var next = terminals[_swapIndex];
        Win32Helper.FocusWindow(next.Handle);
        AddActivity($"Swapped to {next.ProcessName}: {Truncate(next.Title, 32)}");
    }

    private void ScanWindows()
    {
        if (!IsRunning) return;

        var windows = Win32Helper.GetVisibleWindows();
        foreach (var win in windows)
        {
            bool isTerminal = TerminalProcesses.Contains(win.ProcessName);
            bool isIde = IdeProcesses.Contains(win.ProcessName);
            if (!isTerminal && !isIde) continue;

            string text = ReadWindowText(win.Handle);
            if (string.IsNullOrWhiteSpace(text)) continue;

            if (isTerminal)
            {
                HandleTerminalText(win, text);
            }
            else if (isIde && AutoEnterEnabled)
            {
                HandleIdeText(win, text);
            }
        }
    }

    private void HandleTerminalText(Win32Helper.WindowInfo win, string text)
    {
        var lines = text.Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        var recentLines = lines.TakeLast(15).ToArray();
        if (recentLines.Length == 0) return;

        for (int i = recentLines.Length - 1; i >= 0; i--)
        {
            string line = recentLines[i];
            string lower = line.ToLowerInvariant();

            if (CliAutoAcceptEnabled && YesNoPatterns.Any(lower.Contains))
            {
                string key = $"yn:{win.Handle}:{line}";
                if (IsOnCooldown(key)) return;
                MarkCooldown(key);

                ScheduleAction(CliEnterDelay, () =>
                {
                    if (!IsRunning) return;
                    Win32Helper.FocusWindow(win.Handle);
                    Win32Helper.SendTextAndEnter("y");
                    EnterPressCount++;
                    AddActivity($"Accepted prompt in {win.ProcessName}");
                    if (PlaySoundOnCompletion) SystemSounds.Asterisk.Play();
                });
                return;
            }

            if (CliAutoPickNumberEnabled && NumberChoicePatterns.Any(lower.Contains))
            {
                string key = $"num:{win.Handle}:{line}";
                if (IsOnCooldown(key)) return;
                MarkCooldown(key);

                ScheduleAction(CliEnterDelay, () =>
                {
                    if (!IsRunning) return;
                    Win32Helper.FocusWindow(win.Handle);
                    Win32Helper.SendEnter();
                    EnterPressCount++;
                    AddActivity($"Picked default option in {win.ProcessName}");
                    if (PlaySoundOnCompletion) SystemSounds.Asterisk.Play();
                });
                return;
            }
        }
    }

    private void HandleIdeText(Win32Helper.WindowInfo win, string text)
    {
        string? matched = GuiPromptReadyIndicators.FirstOrDefault(
            ind => text.Contains(ind, StringComparison.OrdinalIgnoreCase));

        if (matched is null) return;

        string key = $"ide:{win.Handle}:{matched}";
        if (IsOnCooldown(key)) return;
        MarkCooldown(key);

        ScheduleAction(EnterDelay, () =>
        {
            if (!IsRunning || !AutoEnterEnabled) return;
            Win32Helper.FocusWindow(win.Handle);
            Win32Helper.SendEnter();
            EnterPressCount++;
            AddActivity($"Pressed Enter in {win.ProcessName}");
        });
    }

    private static string ReadWindowText(IntPtr hwnd)
    {
        try
        {
            var root = AutomationElement.FromHandle(hwnd);
            if (root is null) return string.Empty;

            if (root.TryGetCurrentPattern(TextPattern.Pattern, out object? tpObj) && tpObj is TextPattern tp)
            {
                return tp.DocumentRange.GetText(4000);
            }

            var sb = new StringBuilder();
            CollectAutomationText(root, sb, 0, 5);
            return sb.ToString();
        }
        catch
        {
            return string.Empty;
        }
    }

    private static void CollectAutomationText(AutomationElement element, StringBuilder sb, int depth, int maxDepth)
    {
        if (depth > maxDepth || sb.Length > 4000) return;

        try
        {
            if (element.TryGetCurrentPattern(TextPattern.Pattern, out object? tpObj) && tpObj is TextPattern tp)
            {
                sb.AppendLine(tp.DocumentRange.GetText(2000));
                return;
            }

            if (element.TryGetCurrentPattern(ValuePattern.Pattern, out object? vpObj) && vpObj is ValuePattern vp)
            {
                if (!string.IsNullOrWhiteSpace(vp.Current.Value))
                    sb.AppendLine(vp.Current.Value);
            }

            string name = element.Current.Name;
            if (!string.IsNullOrWhiteSpace(name))
                sb.AppendLine(name);

            var children = element.FindAll(TreeScope.Children, Condition.TrueCondition);
            int count = Math.Min(children.Count, 20);
            for (int i = 0; i < count; i++)
            {
                CollectAutomationText(children[i], sb, depth + 1, maxDepth);
            }
        }
        catch
        {
            // Ignore transient UI Automation errors when windows close or update
        }
    }

    private bool IsOnCooldown(string key)
    {
        if (_answeredCooldowns.TryGetValue(key, out DateTime expiresAt))
        {
            if (DateTime.UtcNow < expiresAt) return true;
        }
        return false;
    }

    private void MarkCooldown(string key)
    {
        _answeredCooldowns[key] = DateTime.UtcNow.AddSeconds(8);
    }

    private static void ScheduleAction(double delaySeconds, Action action)
    {
        var timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(Math.Max(0.1, delaySeconds)) };
        timer.Tick += (_, _) =>
        {
            timer.Stop();
            action();
        };
        timer.Start();
    }

    private void AddActivity(string message)
    {
        string entry = $"[{DateTime.Now:HH:mm:ss}] {message}";
        ActivityLog.Insert(0, entry);
        while (ActivityLog.Count > 50)
        {
            ActivityLog.RemoveAt(ActivityLog.Count - 1);
        }
    }

    private static string Truncate(string s, int max) => s.Length <= max ? s : s[..max] + "...";

    private void OnPropertyChanged([CallerMemberName] string? name = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
}
