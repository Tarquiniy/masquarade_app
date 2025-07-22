import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

class CoinFlipScreen extends StatefulWidget {
  @override
  _CoinFlipScreenState createState() => _CoinFlipScreenState();
}

class _CoinFlipScreenState extends State<CoinFlipScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  final Random _random = Random();
  bool _isFlipping = false;
  String _result = '';
  String _side = 'Орёл';
  double _rotation = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 1000),
    );

    _animation = Tween<double>(begin: 0, end: 1).animate(_controller)
      ..addListener(() {
        setState(() {
          _rotation = _animation.value * 10 * pi;
        });
      })
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _determineResult();
        }
      });
  }

  void _flipCoin() {
    if (_isFlipping) return;

    setState(() {
      _isFlipping = true;
      _result = '';
      _side = _random.nextBool() ? 'Орёл' : 'Решка';
    });

    _controller.reset();
    _controller.forward();
  }

  void _determineResult() {
    setState(() {
      _result = _side;
      _isFlipping = false;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Бросок монеты'),
        backgroundColor: Color.fromARGB(255, 14, 0, 0),
      ),
      backgroundColor: Color(0xFF1a0000),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Transform(
              alignment: Alignment.center,
              transform: Matrix4.rotationY(_rotation),
              child: Container(
                width: 150,
                height: 150,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.amber,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.5),
                      spreadRadius: 2,
                      blurRadius: 10,
                      offset: Offset(0, 5),
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    _rotation ~/ pi % 2 == 0 ? 'Орёл' : 'Решка',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.brown[800],
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(height: 30),
            if (_result.isNotEmpty)
              Text(
                'Результат: $_result',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.amber,
                ),
              ),
            SizedBox(height: 30),
            ElevatedButton.icon(
              onPressed: _flipCoin,
              icon: Icon(Icons.autorenew, color: Colors.amber),
              label: Text(
                'Бросить монетку',
                style: TextStyle(color: Colors.amber),
              ),
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                backgroundColor: Color.fromARGB(255, 119, 4, 4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
