using System.Windows;

namespace VibeAutoEnter;

public partial class MainWindow : Window
{
    private readonly WindowsAutoEnterMonitor _monitor = new();

    public MainWindow()
    {
        InitializeComponent();
        DataContext = _monitor;
    }

    private void ToggleMonitoring_Click(object sender, RoutedEventArgs e)
    {
        _monitor.ToggleMonitoring();
    }
}
