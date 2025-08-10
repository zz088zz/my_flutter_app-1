import 'package:flutter/material.dart';

class EVCarImage extends StatelessWidget {
  final double width;
  final double height;
  
  const EVCarImage({
    Key? key,
    this.width = 200,
    this.height = 120,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.2),
            spreadRadius: 2,
            blurRadius: 5,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            // Modern EV car illustration
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Theme.of(context).primaryColor.withOpacity(0.1),
                    Theme.of(context).primaryColor.withOpacity(0.05),
                  ],
                ),
              ),
            ),
            Center(
              child: Icon(
                Icons.electric_car,
                size: height * 0.6,
                color: Theme.of(context).primaryColor.withOpacity(0.8),
              ),
            ),
            // Charging animation dots
            Positioned(
              right: 20,
              top: height * 0.4,
              child: Row(
                children: List.generate(3, (index) => 
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Icon(
                      Icons.bolt,
                      size: 16,
                      color: Theme.of(context).primaryColor.withOpacity(0.6),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
} 