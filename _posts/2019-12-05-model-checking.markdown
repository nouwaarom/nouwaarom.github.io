---
layout: post
title:  "Model Checking"
date:   2019-12-05 17:30:00 +0100
categories: misc 
---

This post is an simple introduction modelchecking.
What I write is based on my limited experience with this subject.
I apologize in advance if I miss something.

The goal of model checking is to verify if the behaviour of a system is as intended.
This verification is especially usefull for safety-critical systems.
Here are some examples:
For the software in a car you want the brake pedal to *always* make the car brake, you do not want the turning on the radio can effect this behaviour.
For the traffic lights of an intersection you *never* want two crossing lanes to have green light at the same time.
A second intended behaviour of a traffic light system is that every lane will get green *eventually*.

In order to verify the behaviour of a system we need two things.
The first thing is a good model of the system.
The second thing is a good description of the intended behaviour of the system.
In the next sections we will give a description of what a "good model" and a "good description" of behaviour might be.
What I will describe is definitely not the only option, or the best option for every system, there are different choices for different types of systems.

### Models 
Let us start with defining what a "good model" might be for checking the behaviour of a system.
A model is a simpler representation of the truth.
We want a model that is as simple as possible, but not so simple that a problemwith the model does not point to a problem in the real system.
This makes sense, right?

Let's take a system and see what we can remove in order to get a simple model that is still usefull.
If we take the example of a traffic-light system for an intersection.
The "real" system includes: lights, controllers and the software they run, a lot of wires, vehicle detection sensors, some buttons for the pedestrians.

Now, what information do we need in order to check the behaviour described above (no crossing lanes have green at the same moment, a lanes will eventually get green)?
For the lights we only care about their state, are they red, orange or green? How they are connected and how bright they are etc. is not important to us.
We are also not interested in the specifics of the buttons, they can be represented as simple binary input: a car is detected, or it is not; there are pedestrians, or there are no pedestrians.

For the controllers we are not interested in the specific hardware or software they use.
We are interested in how a controller responds given a certain input and having a certain *state*.
The controller has a *state* that is based on its previous inputs.
We are not interested in what exactly this state is. e.g. we do not care the values of variables in the controller or where in it's program it is executing.
What we are interested in is which states a certain input can be given and in which states a certain output is produced.

So, what are we interested in?
Given the following crossing:
![Crossing](/assets/img/crossing.png){:width="100%"}
Where every lane has one light for every direction and a sensor that detects if there is a vehicle in that lane.

And the following control system:
```
car_north = false
car_east = false
...

north_light = red
east_light = red
west_light = red
south_light = red

repeat {
    if (car_north AND east_light=red AND west_light=red AND south_light=red) {
        north_light = green
        wait(5s)
        north_light = orange
        wait(2s)
        north_light = red
    }
    if (car_east AND ...
}
```
where `car_x` is changed by the sensor. 

This behaviour might be modeled as:
The lights are displayed as (north\_color, east\_color, west\_color, south\_color).

- state1: (red,red,red,red) transitions to (state2, state4)
- state2: (green,red,red,red) transitions to (state3)
- state3: (orange,red,red,red) transitinos to (state4)
- state4: (red,red,red,red) transitions to (state5)

- state5: (red,red,red,red) transitions to (state6, state8)
- state6: (red,green,red,red) transitions to (state7)
- state7: (red,orange,red,red) transitinos to (state8)
- state8: (red,red,red,red) transitions to ...
...

This way of describing the system preserves the required information to do analysis of the behaviour of the system but removes all other information.

### Behaviour
This post is already long enough and I don't want to cause you a headache.
How to behave will be handled in the next post.
