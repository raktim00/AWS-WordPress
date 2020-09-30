# The Full procedure of doing this practical you can find in below link :

## “Secure Architecture on AWS ( Hosting WordPress on Public and Database on Private Subnet )” by Raktim Midya - https://link.medium.com/7R7TZnmfbab

## Problem Statement :
### We have to create a web portal for our company with all the security as much as possible.

### So, we use WordPress software with dedicated database server.Database should not be accessible from the outside world for security purposes. We only need to public the WordPress to clients.

#### So here are the steps for proper understanding!
- 1. Write an Infrastructure as code using terraform, which automatically create a VPC.
- 2. In that VPC we have to create 2 subnets:
- 3. public subnet - Accessible for Public World! 
- 4. private subnet - Restricted for Public World! 
- 5. Create a public facing internet gateway for connect our VPC/Network to the internet world and attach this gateway to our VPC.
- 6. Create a routing table for Internet gateway so that instance can connect to outside world, update and associate it with public subnet.
- 7. Create a NAT gateway for connect our VPC/Network to the internet world and attach this gateway to our VPC in the public network
- 8. Update the routing table of the private subnet, so that to access the internet it uses the NAT gateway created in the public subnet
- 9. Launch an ec2 instance which has WordPress setup already having the security group allowing port 80 so that our client can connect to our WordPress site. Also attach the key to instance for further login into it.
- 10. Launch an ec2 instance which has MYSQL setup already with security group allowing port 3306 in private subnet so that our WordPress vm can connect with the same. Also attach the key with the same.
##### Note: WordPress instance has to be part of public subnet so that our client can connect our site. MySQL instance has to be part of private subnet so that outside world can’t connect to it.
##### Don’t forgot to add auto ip assign and auto dns name assignment option to be enabled.
