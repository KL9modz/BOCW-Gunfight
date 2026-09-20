using System.Windows;

namespace GfPanel.Views;

public partial class PromptWindow : Window
{
    public PromptWindow() { InitializeComponent(); }

    public static string? Ask(Window? owner, string text, string initial)
    {
        var w = new PromptWindow { Owner = owner };
        w.Label.Text = text;
        w.Box.Text = initial;
        w.Box.SelectAll();
        w.Loaded += (_, _) => w.Box.Focus();
        return w.ShowDialog() == true ? w.Box.Text : null;
    }

    private void Ok_Click(object sender, RoutedEventArgs e) { DialogResult = true; Close(); }
    private void Cancel_Click(object sender, RoutedEventArgs e) { DialogResult = false; Close(); }
}
