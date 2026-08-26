# Changelog

## 5.0.5

First release of CpapDash as a Home Assistant add-on.

5.0.5 rather than an earlier version because it is the first release whose web UI
survives being served underneath an Ingress prefix. On 5.0.4 the page loads and
then fails every asset and every API call, so there was nothing to package.

The add-on is a thin layer over that published image: an entrypoint that turns
add-on options into CpapDash configuration and asks the Supervisor for the MQTT
broker's credentials, so there is nothing to type and no second password. With no
broker configured it degrades to the web UI alone rather than refusing to start.

The entities were already there: CpapDash has published MQTT discovery for its
sensors, supplies, cleaning schedules and live session state for a long time, so
no custom integration is needed and none is offered.
