using System.Windows;
using System.Windows.Controls;
using GfPanel.ViewModels;

namespace GfPanel.Views;

public partial class RaceView : UserControl
{
    private RaceVM? _race;

    public RaceView()
    {
        InitializeComponent();
        DataContextChanged += OnDataContext;
    }

    /// <summary>RaceVM.FitRequested (a new map, a first track, Fit): the plot fits its content.</summary>
    private void OnDataContext(object sender, DependencyPropertyChangedEventArgs e)
    {
        if (_race != null) _race.FitRequested -= Fit;
        _race = (DataContext as MainViewModel)?.Race;
        if (_race != null) _race.FitRequested += Fit;
    }

    private void Fit() => Plot.FitToContent();
}
