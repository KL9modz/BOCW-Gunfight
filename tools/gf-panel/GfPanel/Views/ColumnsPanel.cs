using System.Windows;
using System.Windows.Controls;

namespace GfPanel.Views;

/// <summary>Lays its children out in 1-3 columns (400 px minimum each), each child dropped into the
/// currently SHORTEST column in order - the rcon tool's layoutColumns(): blocks never reshuffle on
/// a height change, only when the column count changes with the width.</summary>
public sealed class BalancedColumnsPanel : Panel
{
    public double ColumnMinWidth { get; set; } = 400;
    public double Gap { get; set; } = 12;
    public int MaxColumns { get; set; } = 3;
    private readonly List<(int Col, double Y)> _slots = new();
    private double _colWidth;

    protected override Size MeasureOverride(Size available)
    {
        var w = double.IsInfinity(available.Width) ? 1200 : available.Width;
        var cols = Math.Clamp((int)Math.Floor((w + Gap) / (ColumnMinWidth + Gap)), 1, MaxColumns);
        _colWidth = (w - Gap * (cols - 1)) / cols;
        var heights = new double[cols];
        _slots.Clear();
        foreach (UIElement child in InternalChildren)
        {
            child.Measure(new Size(_colWidth, double.PositiveInfinity));
            var c = 0;
            for (var j = 1; j < cols; j++) if (heights[j] < heights[c] - 1) c = j;
            _slots.Add((c, heights[c]));
            heights[c] += child.DesiredSize.Height + Gap;
        }
        return new Size(w, Math.Max(0, heights.Max() - Gap));
    }

    protected override Size ArrangeOverride(Size final)
    {
        for (var i = 0; i < InternalChildren.Count && i < _slots.Count; i++)
        {
            var child = InternalChildren[i];
            var (col, y) = _slots[i];
            child.Arrange(new Rect(col * (_colWidth + Gap), y, _colWidth, child.DesiredSize.Height));
        }
        return final;
    }
}

public sealed class ColumnsPanel : ItemsControl
{
    public ColumnsPanel()
    {
        ItemsPanel = new ItemsPanelTemplate(new FrameworkElementFactory(typeof(BalancedColumnsPanel)));
    }
}
