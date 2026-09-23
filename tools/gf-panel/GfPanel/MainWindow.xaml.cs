using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Threading;
using GfPanel.Services;
using GfPanel.ViewModels;

namespace GfPanel;

public partial class MainWindow : Window
{
    private readonly MainViewModel _vm;
    private readonly Prefs _prefs;

    public MainWindow()
    {
        InitializeComponent();
        _prefs = Prefs.Load();
        _vm = new MainViewModel(_prefs) { Owner = this };
        DataContext = _vm;
        Width = Math.Max(MinWidth, _prefs.WindowWidth);
        Height = Math.Max(MinHeight, _prefs.WindowHeight);
        if (_prefs.WindowMaximized) WindowState = WindowState.Maximized;
        SidebarCol.Width = new GridLength(Math.Clamp(_prefs.SidebarWidth, SidebarCol.MinWidth, SidebarCol.MaxWidth));
        _vm.TabRequested += SelectTab;
        _vm.RevealRow += RevealRow;
        SelectTab(App.StartTab ?? _prefs.LastTab);
        PreviewKeyDown += OnKey;
        KeyDown += OnKeyBubbled;
        SourceInitialized += (_, _) => _vm.Overlay.Attach(this);   // the hotkey needs the HWND
        Closing += (_, _) =>
        {
            _vm.Overlay.Detach();   // first: an overlay still up would be saved as the window's size
            _prefs.WindowWidth = RestoreBounds.Width; _prefs.WindowHeight = RestoreBounds.Height;
            _prefs.WindowMaximized = WindowState == WindowState.Maximized;
            _prefs.SidebarWidth = SidebarCol.ActualWidth;
            _vm.Shutdown();
        };
        Title = "Gunfight Host Panel" + (App.DryRun ? "  [DRY RUN]" : "");
    }

    private void SelectTab(string tag)
    {
        foreach (TabItem t in Tabs.Items)
            if ((t.Tag as string) == tag) { Tabs.SelectedItem = t; return; }
    }

    private void Tabs_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (e.Source != Tabs) return;
        if (Tabs.SelectedItem is TabItem t && t.Tag is string tag) { _prefs.LastTab = tag; }
    }

    private void Splitter_DragCompleted(object sender, System.Windows.Controls.Primitives.DragCompletedEventArgs e)
    {
        _prefs.SidebarWidth = SidebarCol.ActualWidth;
        _prefs.Save();
    }

    private void OnKey(object sender, KeyEventArgs e)
    {
        if (e.Key == Key.Escape && SearchBox.IsKeyboardFocused) { _vm.Search = ""; Keyboard.ClearFocus(); e.Handled = true; return; }
        if (e.Key == Key.OemQuestion && Keyboard.Modifiers == ModifierKeys.None && Keyboard.FocusedElement is not TextBox)
        {
            SearchBox.Focus(); SearchBox.SelectAll(); e.Handled = true;
        }
    }

    /// <summary>Esc that nothing else wanted (a dropdown closing, the search clearing) puts the overlay away.</summary>
    private void OnKeyBubbled(object sender, KeyEventArgs e)
    {
        if (e.Key == Key.Escape && !e.Handled && _vm.Overlay.Active) { _vm.Overlay.Exit(focusGame: true); e.Handled = true; }
    }

    /// <summary>Scroll a settings row into view and flash it (the search's "go to").</summary>
    private void RevealRow(SettingRowVM row)
    {
        Dispatcher.BeginInvoke(DispatcherPriority.Loaded, () =>
        {
            var fe = FindByDataContext(this, row);
            if (fe == null) return;
            fe.BringIntoView();
            if (fe is Panel p)
            {
                var old = p.Background;
                p.Background = (Brush)FindResource("AcDim");
                var t = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(1600) };
                t.Tick += (_, _) => { t.Stop(); p.Background = old; };
                t.Start();
            }
        });
    }

    private static FrameworkElement? FindByDataContext(DependencyObject root, object ctx)
    {
        var n = VisualTreeHelper.GetChildrenCount(root);
        for (var i = 0; i < n; i++)
        {
            var child = VisualTreeHelper.GetChild(root, i);
            if (child is Grid g && ReferenceEquals(g.DataContext, ctx) && g.ToolTip != null) return g;
            var r = FindByDataContext(child, ctx);
            if (r != null) return r;
        }
        return null;
    }
}
