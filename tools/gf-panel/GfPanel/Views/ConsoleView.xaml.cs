using System.Windows.Controls;
using System.Windows.Input;
using GfPanel.ViewModels;

namespace GfPanel.Views;

public partial class ConsoleView : UserControl
{
    public ConsoleView() { InitializeComponent(); }

    private void Input_PreviewKeyDown(object sender, KeyEventArgs e)
    {
        if (DataContext is not MainViewModel vm) return;
        if (e.Key == Key.Enter) { vm.Console.Send.Execute(null); e.Handled = true; }
        else if (e.Key == Key.Up) { vm.Console.HistoryUp(); e.Handled = true; }
        else if (e.Key == Key.Down) { vm.Console.HistoryDown(); e.Handled = true; }
    }
}
