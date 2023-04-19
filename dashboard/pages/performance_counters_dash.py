import pandas as pd

import dash
from dash import html, dcc, callback, Input, Output
from plotly.subplots import make_subplots
import plotly.graph_objects as go
import plotly.express as px

dash.register_page(__name__)

df = pd.read_csv("data/performance_counters.csv", decimal=',')
df['report_time'] = pd.to_datetime(df['report_time'], format="%d/%m/%Y %H:%M:%S")

layout = html.Div(children=[
    html.H1(children='Performance Counters'),
    html.Div([
        dcc.Graph(id='graph_performance')
    ]),
    html.Div([
        html.Br(),
        html.Label(['Select metrics:'], style={'font-weight': 'bold', "text-align": "center"}),
        dcc.Dropdown(id='metric1',
                     options=[{'label': x, 'value': x} for x in
                              sorted(set(df['counter_name']))],
                     value='Active Temp Tables',
                     multi=False,
                     disabled=False,
                     clearable=True,
                     searchable=True,
                     placeholder='Choose Metric...',
                     className='form-dropdown',
                     style={'width': "90%"},
                     persistence='string',
                     persistence_type='memory'),

        dcc.Dropdown(id='metric2',
                     options=[{'label': x, 'value': x} for x in
                              sorted(set(df['counter_name']))],
                     # value='Asian',
                     multi=False,
                     clearable=True,
                     searchable=True,
                     placeholder='Choose Metric...',
                     className='form-dropdown',
                     persistence='string',
                     style={'width': "90%"},
                     persistence_type='session'),
        html.Br(),
        html.Br(),
        html.Br()
    ], className='three columns'),
])


@callback(
    Output('graph_performance', 'figure'),
    [Input('metric1', 'value'),
     Input('metric2', 'value')]
)
def build_graph(metric1, metric2):
    if metric1 is not None and metric2 is not None:
        df1 = df[df['counter_name'] == metric1]
        df2 = df[df['counter_name'] == metric2]

        # Create figure with secondary y-axis
        fig = make_subplots(specs=[[{"secondary_y": True}]])
        # Add traces
        fig.add_trace(
            go.Scatter(x=df1['report_time'], y=df1['cntr_value'], name=metric1, mode='lines'),
            secondary_y=False,
        )
        fig.add_trace(
            go.Scatter(x=df2['report_time'], y=df2['cntr_value'], name=metric2, mode='lines'),
            secondary_y=True,
        )
        # Set y-axes titles
        fig.update_yaxes(
            title_text="cntr_value",
            secondary_y=False)
        fig.update_yaxes(
            title_text="<b>secondary</b> cntr_value",
            secondary_y=True)

    else:
        dff = df[(df['counter_name'] == metric1) |
                 (df['counter_name'] == metric2)]
        fig = px.line(dff, x="report_time", y="cntr_value", color='counter_name', height=600)

    fig.update_layout(yaxis={'title': 'cntr_value'},
                      title={'text': 'SQL Server performance dashboard',
                             'font': {'size': 28}, 'x': 0.5, 'xanchor': 'center'})
    return fig
