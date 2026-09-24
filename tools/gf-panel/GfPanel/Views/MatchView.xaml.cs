using System.Windows.Controls;
using System.Windows.Input;
using GfPanel.ViewModels;

namespace GfPanel.Views;

public partial class MatchView : UserControl
{
    public MatchView() { InitializeComponent(); }

    /// <summary>MESSAGES: Enter sends (moved here with the composer from the old DASHBOARD).</summary>
    private void MsgBox_KeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key == Key.Enter && DataContext is MainViewModel vm) { vm.Message.Send.Execute(null); e.Handled = true; }
    }
}
