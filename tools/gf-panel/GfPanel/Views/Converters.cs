using System.Globalization;
using System.Windows;
using System.Windows.Data;
using System.Windows.Media;

namespace GfPanel.Views;

public sealed class BoolToVis : IValueConverter
{
    public bool Invert { get; set; }
    public object Convert(object value, Type t, object p, CultureInfo c) => (value is bool b && b) != Invert ? Visibility.Visible : Visibility.Collapsed;
    public object ConvertBack(object value, Type t, object p, CultureInfo c) => throw new NotSupportedException();
}

public sealed class NullToVis : IValueConverter
{
    public bool Invert { get; set; }
    public object Convert(object value, Type t, object p, CultureInfo c) => (value != null && !(value is string s && s.Length == 0)) != Invert ? Visibility.Visible : Visibility.Collapsed;
    public object ConvertBack(object value, Type t, object p, CultureInfo c) => throw new NotSupportedException();
}

/// <summary>A status / team / level KEY to a brush from the theme: "on" "off" "err" "warn" | "allies" "axis" "spec" | "ok" "wn" "err" "info".</summary>
public sealed class KeyToBrush : IValueConverter
{
    public object Convert(object value, Type t, object p, CultureInfo c)
    {
        var key = (value?.ToString() ?? "").ToLowerInvariant();
        var res = key switch
        {
            "on" or "ok" or "true" => "Ok",
            "err" or "ng" or "fail" or "timeout" => "Ng",
            "warn" or "wn" => "Wn",
            "allies" or "a" => "TeamA",
            "axis" or "x" => "TeamX",
            "spec" or "s" or "spectator" => "TeamS",
            "in" or "info" or "sent" => "Ac",
            "ack" => "Ok",
            _ => "Dm",
        };
        return Application.Current.TryFindResource(res) as Brush ?? Brushes.Gray;
    }
    public object ConvertBack(object value, Type t, object p, CultureInfo c) => throw new NotSupportedException();
}

public sealed class TeamToBg : IValueConverter
{
    public object Convert(object value, Type t, object p, CultureInfo c)
    {
        var key = (value?.ToString() ?? "").ToLowerInvariant();
        var res = key switch { "allies" => "TeamADim", "axis" => "TeamXDim", _ => "TeamSDim" };
        return Application.Current.TryFindResource(res) as Brush ?? Brushes.Transparent;
    }
    public object ConvertBack(object value, Type t, object p, CultureInfo c) => throw new NotSupportedException();
}

public sealed class EffToBrush : IValueConverter
{
    public object Convert(object value, Type t, object p, CultureInfo c)
    {
        var res = (value?.ToString() ?? "") switch { "LIVE" => "Ok", "RESTART" => "Ng", _ => "Wn" };
        return Application.Current.TryFindResource(res) as Brush ?? Brushes.Gray;
    }
    public object ConvertBack(object value, Type t, object p, CultureInfo c) => throw new NotSupportedException();
}

public sealed class HexToBrush : IValueConverter
{
    public object Convert(object value, Type t, object p, CultureInfo c)
    {
        try { return new SolidColorBrush((Color)ColorConverter.ConvertFromString(value?.ToString() ?? "#888")); } catch { return Brushes.Gray; }
    }
    public object ConvertBack(object value, Type t, object p, CultureInfo c) => throw new NotSupportedException();
}

public sealed class IntToString : IValueConverter
{
    public object Convert(object value, Type t, object p, CultureInfo c) => value?.ToString() ?? "";
    public object ConvertBack(object value, Type t, object p, CultureInfo c) => int.TryParse(value?.ToString(), out var n) ? n : Binding.DoNothing;
}

/// <summary>int == parameter (radio buttons over an int property); ConvertBack yields the parameter when checked.</summary>
public sealed class IntEquals : IValueConverter
{
    public object Convert(object value, Type t, object p, CultureInfo c) => value is int i && int.TryParse(p?.ToString(), out var n) && i == n;
    public object ConvertBack(object value, Type t, object p, CultureInfo c) => value is true && int.TryParse(p?.ToString(), out var n) ? n : Binding.DoNothing;
}

public sealed class NotConverter : IValueConverter
{
    public object Convert(object value, Type t, object p, CultureInfo c) => value is not true;
    public object ConvertBack(object value, Type t, object p, CultureInfo c) => value is not true;
}

public sealed class CountToVis : IValueConverter
{
    public object Convert(object value, Type t, object p, CultureInfo c) => value is int i && i > 0 ? Visibility.Visible : Visibility.Collapsed;
    public object ConvertBack(object value, Type t, object p, CultureInfo c) => throw new NotSupportedException();
}

/// <summary>A Freezable that carries the view's DataContext into places outside the visual tree
/// (a CompositeCollection's CollectionContainer has no DataContext of its own).</summary>
public sealed class BindingProxy : Freezable
{
    public static readonly DependencyProperty DataProperty = DependencyProperty.Register(nameof(Data), typeof(object), typeof(BindingProxy));
    public object? Data { get => GetValue(DataProperty); set => SetValue(DataProperty, value); }
    protected override Freezable CreateInstanceCore() => new BindingProxy();
}
