using System.Windows.Controls;
using System.Windows.Input;
using GfPanel.ViewModels;

namespace GfPanel.Views;

public partial class DashboardView : UserControl
{
    public DashboardView() { InitializeComponent(); }

    private void MsgBox_KeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key == Key.Enter && DataContext is MainViewModel vm) { vm.Message.Send.Execute(null); e.Handled = true; }
    }
}
