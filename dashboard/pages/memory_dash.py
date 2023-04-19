import pandas as pd

import dash
from dash import html, dcc, callback, Input, Output
import plotly.express as px

dash.register_page(__name__)

df = pd.read_csv("data\\memory.csv", decimal=',')
metrics = ['Physical memory in use (MB)',
           'Locked page allocations (MB)', 'Page faults', 'Memory utilisation %']
df['report_time'] = pd.to_datetime(df['report_time'], format="%d/%m/%Y %H:%M:%S")

layout = html.Div(children=[
    html.H1(children='Memory'),
    html.Div([
        dcc.Graph(id='graph_memory')
    ]),
    html.Div([
        html.Br(),
        html.Label(['Select metrics:'], style={'font-weight': 'bold', "text-align": "center"}),
        dcc.Dropdown(id='metric',
                     options=[{'label': x, 'value': x} for x in
                              sorted(metrics)],
                     value='Memory utilisation %',
                     multi=False,
                     disabled=False,
                     clearable=False,
                     searchable=True,
                     placeholder='Choose Metric...',
                     className='form-dropdown',
                     style={'width': "90%"},
                     persistence='string',
                     persistence_type='memory'),
        html.Br(),
        html.Br(),
        html.Br()
    ], className='three columns'),
])


@callback(
    Output('graph_memory', 'figure'),
    Input('metric', 'value'),
)
def build_graph(metric):
    fig = px.line(df, x="report_time", y=metric, height=600, labels=[metrics])

    fig.update_layout(yaxis={'title': 'cntr_value'},
                      title={'text': 'SQL Server performance dashboard',
                             'font': {'size': 28}, 'x': 0.5, 'xanchor': 'center'})
    return fig
