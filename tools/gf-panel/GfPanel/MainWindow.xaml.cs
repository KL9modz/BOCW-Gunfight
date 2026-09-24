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
        Closing += (_, _) =>
        {
            _prefs.WindowWidth = RestoreBounds.Width; _prefs.WindowHeight = RestoreBounds.Height;
            _prefs.WindowMaximized = WindowState == WindowState.Maximized;
            _prefs.SidebarWidth = SidebarCol.ActualWidth;
            _vm.Shutdown();
        };
        Title = "Gunfight Host Panel" + (App.DryRun ? "  [DRY RUN]" : "");
        if (App.FakeMenu)
            Loaded += async (_, _) =>
            {
                await Task.Delay(1500);
                var row = _vm.Players.Rows.FirstOrDefault(r => r.ShowGiveMenu) ?? _vm.Players.Rows.FirstOrDefault(r => r.HasMenu);
                if (row == null || FindByContext(this, row) is not Border b || b.ContextMenu is not ContextMenu cm) return;
                cm.PlacementTarget = b;
                cm.Placement = System.Windows.Controls.Primitives.PlacementMode.Bottom;
                cm.IsOpen = true;
                await Task.Delay(600);
                if (cm.Items.OfType<MenuItem>().FirstOrDefault(m => (m.Header as string)?.Contains("Teleport") == true) is MenuItem tp)
                {
                    tp.IsSubmenuOpen = true;
                    await Task.Delay(600);
                    if (tp.Items.OfType<MenuItem>().FirstOrDefault(m => (m.Header as string)?.Contains("player") == true) is MenuItem to)
                        to.IsSubmenuOpen = true;
                }
            };
        if (App.ExportSpawns)
            Loaded += async (_, _) =>
            {
                await _vm.Spawns.SaveAllImages((path, atlas, art, align, layout) =>
                    Views.SpawnPlot.SaveOffscreen(path, 2400, 1500, atlas, art, align, "all", layout, true), openFolder: false);
                Close();
            };
    }

    /// <summary>Show a page by its Tag, or a page's sub-tab by the sub-tab's Tag (spawns = MAPS &amp; SPAWNS → SPAWN
    /// ATLAS, entities = FORGE → SPAWNED ENTITIES, console = DIAGNOSTICS → CONSOLE). A page whose own sub-tab carries
    /// the page's tag (maps, forge, diagnostics) opens on that sub-tab. The pre-redesign tags still work (--tab, an old
    /// LastTab): favorites → MATCH (its ★ PINNED SETTINGS), dashboard → RULES, advanced → DIAGNOSTICS, tools → SANDBOX.</summary>
    private void SelectTab(string tag)
    {
        tag = tag switch { "favorites" => "match", "dashboard" => "rules", "advanced" => "diagnostics", "tools" => "sandbox", _ => tag };
        foreach (TabItem page in Tabs.Items)
        {
            var sub = SubTabs(page);
            var inner = sub?.Items.OfType<TabItem>().FirstOrDefault(t => (t.Tag as string) == tag);
            if ((page.Tag as string) != tag && inner == null) continue;
            // the sub-tab first: Tabs_SelectionChanged then sees the page arrive already on it, so the entity list
            // never switches on for a moment on the way to another FORGE sub-tab
            if (inner != null) sub!.SelectedItem = inner;
            Tabs.SelectedItem = page;
            return;
        }
    }

    private readonly Dictionary<TabItem, TabControl?> _subTabs = new();
    /// <summary>A page's own sub-tab strip, found in the logical tree (it exists before the page is first shown).</summary>
    private TabControl? SubTabs(TabItem page)
    {
        if (!_subTabs.TryGetValue(page, out var tc)) _subTabs[page] = tc = FindTabControl(page);
        return tc;
    }
    private static TabControl? FindTabControl(DependencyObject node)
    {
        foreach (var child in LogicalTreeHelper.GetChildren(node).OfType<DependencyObject>())
            if ((child as TabControl ?? FindTabControl(child)) is TabControl found) return found;
        return null;
    }

    private void Tabs_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        // a sub-tab strip's change bubbles here too (from inside a page with Source = the page's UserControl, hence
        // OriginalSource), and so does every combo box and list on the pages - only a tab strip matters
        if (e.OriginalSource is not TabControl) return;
        if (Tabs.SelectedItem is not TabItem page || page.Tag is not string tag) return;
        var shown = SubTabs(page)?.SelectedItem is TabItem { Tag: string sub } ? sub : tag;
        _prefs.LastTab = shown;                           // reopens on the sub-tab too
        _vm.Entities.IsActive = shown == "entities";      // the entity list is read only while FORGE → SPAWNED ENTITIES shows
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

    private static FrameworkElement? FindByContext(DependencyObject root, object ctx)
    {
        var n = VisualTreeHelper.GetChildrenCount(root);
        for (var i = 0; i < n; i++)
        {
            var child = VisualTreeHelper.GetChild(root, i);
            if (child is Border b && ReferenceEquals(b.DataContext, ctx) && b.ContextMenu != null) return b;
            var r = FindByContext(child, ctx);
            if (r != null) return r;
        }
        return null;
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
