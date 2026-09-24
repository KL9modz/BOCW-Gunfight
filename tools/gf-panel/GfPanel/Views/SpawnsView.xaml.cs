using System.IO;
using System.Windows;
using System.Windows.Controls;
using GfPanel.ViewModels;

namespace GfPanel.Views;

public partial class SpawnsView : UserControl
{
    public SpawnsView() { InitializeComponent(); }

    private SpawnsVM? Vm => DataContext as SpawnsVM;

    private void Fit_Click(object sender, RoutedEventArgs e) => Plot.ResetView();

    private void SaveImage_Click(object sender, RoutedEventArgs e)
    {
        var vm = Vm;
        if (vm?.Atlas == null) return;
        var path = Path.Combine(vm.ExportDir, $"{vm.Atlas.Map}-{DateTime.Now:yyyyMMdd-HHmmss}.png");
        try { Plot.SavePng(path, 2); vm.ImageSaved(path); }
        catch (Exception ex) { vm.ImageFailed(ex.Message); }
    }

    private async void SaveAll_Click(object sender, RoutedEventArgs e)
    {
        var vm = Vm;
        if (vm == null) return;
        var north = vm.NorthUp;
        await vm.SaveAllImages((path, atlas, art, align, layout) => SpawnPlot.SaveOffscreen(path, 2400, 1500, atlas, art, align, "all", layout, north));
    }
}
